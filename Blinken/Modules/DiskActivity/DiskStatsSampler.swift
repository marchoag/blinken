//
//  DiskStatsSampler.swift
//  Blinken
//
//  Polls IOKit IOBlockStorageDriver statistics on a dedicated background queue
//  and feeds the aggregator on the main actor. Adaptive rate: 30Hz while disk
//  activity is happening, 5Hz after sustained idleness (PRD §2.3 originally
//  specced 120Hz, but that produced "High" energy impact in Activity Monitor
//  for what's effectively a small ambient indicator — 30Hz active is still
//  visually smooth on a 14pt LED, and idle throttling lets the SoC sleep).
//

import Foundation
import IOKit

/// Drives the disk pipeline: polls IOKit on a `.utility` queue, sums cumulative
/// bytes read/written across physical block devices, and hops to the main actor
/// to feed the `DiskStatsAggregator`.
///
/// `@unchecked Sendable`: all mutable state is touched only on `queue` (a serial
/// dispatch queue), which is the synchronization domain. The only cross-queue
/// hand-off is the per-tick ingest, which carries value types to the main actor.
final class DiskStatsSampler: @unchecked Sendable {

    // MARK: - Configuration

    /// Sampling rate while disk activity is observed.
    nonisolated static let activeHz = 30
    /// Sampling rate after `idleThresholdSeconds` of unchanged byte counters.
    /// Drops kernel wakeups so an idle Mac stays in low-power states (Activity
    /// Monitor's "Energy Impact" reads Low instead of High).
    nonisolated static let idleHz = 5
    /// Seconds of unchanged byte counters before throttling down to `idleHz`.
    nonisolated static let idleThresholdSeconds: Double = 3.0

    private static let activeIntervalNanos = 1_000_000_000 / activeHz
    private static let idleIntervalNanos = 1_000_000_000 / idleHz
    /// ±5ms jitter budget — the timer may coalesce within this rather than
    /// burst-sample to catch up (PRD §2.3, §5).
    private static let leewayNanos = 5_000_000

    // MARK: - State (touched only on `queue`)

    private let aggregator: DiskStatsAggregator
    private let queue = DispatchQueue(label: "com.axiomic.blinken.disk-sampler", qos: .utility)
    private var timer: DispatchSourceTimer?

    private var tickCount: UInt64 = 0
    private var lastRead: UInt64 = 0
    private var lastWritten: UInt64 = 0
    private var quietTicks: UInt64 = 0
    private var inIdleMode = false
    private var lastHeartbeatAt: Double = 0

    init(aggregator: DiskStatsAggregator) {
        self.aggregator = aggregator
    }

    // MARK: - Lifecycle

    /// Starts sampling. Idempotent.
    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(),
                            repeating: .nanoseconds(Self.activeIntervalNanos),
                            leeway: .nanoseconds(Self.leewayNanos))
            source.setEventHandler { [self] in tick() }
            timer = source
            source.resume()
            Log.sampling.debug("DiskStatsSampler started at \(Self.activeHz, privacy: .public)Hz (idle throttle: \(Self.idleHz, privacy: .public)Hz after \(Self.idleThresholdSeconds, privacy: .public)s)")
        }
    }

    /// Stops sampling.
    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    // MARK: - Per-tick sampling

    private func tick() {
        // Monotonic clock — unaffected by wall-clock adjustments.
        let timestamp = ProcessInfo.processInfo.systemUptime
        let totals = Self.readPhysicalDiskTotals()
        tickCount &+= 1

        // Adaptive rate: if the cumulative counters didn't move, count idle ticks
        // and eventually throttle down. First sign of activity wakes us back up.
        let activityChanged = totals.read != lastRead || totals.written != lastWritten
        lastRead = totals.read
        lastWritten = totals.written

        if activityChanged {
            quietTicks = 0
            if inIdleMode { switchToActive() }
        } else {
            quietTicks &+= 1
            if !inIdleMode {
                let secondsQuiet = Double(quietTicks) / Double(Self.activeHz)
                if secondsQuiet >= Self.idleThresholdSeconds {
                    switchToIdle()
                }
            }
        }

        // ~1Hz heartbeat regardless of sampling mode — lets `log stream` confirm
        // the pipeline is alive without depending on tick cadence.
        if timestamp - lastHeartbeatAt >= 1.0 {
            lastHeartbeatAt = timestamp
            Log.sampling.debug("disk sample #\(self.tickCount, privacy: .public): read=\(totals.read, privacy: .public)B write=\(totals.written, privacy: .public)B mode=\(self.inIdleMode ? "idle" : "active", privacy: .public)")
        }

        // Hop to the main actor where the aggregator publishes. `assumeIsolated`
        // is valid because we are on the main thread inside this async block.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.aggregator.ingest(timestamp: timestamp,
                                       totalBytesRead: totals.read,
                                       totalBytesWritten: totals.written)
            }
        }
    }

    // MARK: - Mode switching

    private func switchToIdle() {
        guard !inIdleMode, let timer = timer else { return }
        inIdleMode = true
        quietTicks = 0
        timer.schedule(deadline: .now() + .nanoseconds(Self.idleIntervalNanos),
                       repeating: .nanoseconds(Self.idleIntervalNanos),
                       leeway: .nanoseconds(Self.leewayNanos))
        Log.sampling.debug("DiskStatsSampler throttled to \(Self.idleHz, privacy: .public)Hz (idle)")
    }

    private func switchToActive() {
        guard inIdleMode, let timer = timer else { return }
        inIdleMode = false
        quietTicks = 0
        timer.schedule(deadline: .now(),
                       repeating: .nanoseconds(Self.activeIntervalNanos),
                       leeway: .nanoseconds(Self.leewayNanos))
        Log.sampling.debug("DiskStatsSampler resumed at \(Self.activeHz, privacy: .public)Hz (activity)")
    }

    // MARK: - IOKit

    /// Sums the cumulative `Bytes (Read)` / `Bytes (Write)` counters across every
    /// `IOBlockStorageDriver`. Each driver instance corresponds to one physical
    /// block device, so summing here gives true physical I/O and sidesteps the
    /// APFS virtual-volume double-counting that enumerating `IOMedia` would
    /// introduce (PRD §2.3).
    private static func readPhysicalDiskTotals() -> (read: UInt64, written: UInt64) {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }

            // Key strings match kIOBlockStorageDriverStatisticsKey /
            // …BytesReadKey / …BytesWriteKey from <IOKit/storage/IOBlockStorageDriver.h>.
            guard let property = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0),
                  let stats = property.takeRetainedValue() as? [String: Any] else {
                continue
            }
            if let read = stats["Bytes (Read)"] as? NSNumber { totalRead &+= read.uint64Value }
            if let written = stats["Bytes (Write)"] as? NSNumber { totalWrite &+= written.uint64Value }
        }
        return (totalRead, totalWrite)
    }
}
