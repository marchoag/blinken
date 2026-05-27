//
//  DiskStatsSampler.swift
//  Blinken
//
//  Polls IOKit IOBlockStorageDriver statistics at 120Hz, summing bytes
//  read/written across physical devices only (PRD §2.3).
//

import Foundation
import IOKit

/// Drives the disk pipeline: on a dedicated `.utility` queue it polls IOKit at
/// 120Hz, sums cumulative bytes read/written across physical block devices, and
/// hops to the main actor to feed the `DiskStatsAggregator`.
///
/// `@unchecked Sendable`: all mutable state is touched only on `queue` (a serial
/// dispatch queue), which is the synchronization domain. The only cross-queue
/// hand-off is the per-tick ingest, which carries value types to the main actor.
final class DiskStatsSampler: @unchecked Sendable {

    private let aggregator: DiskStatsAggregator
    private let queue = DispatchQueue(label: "com.axiomic.blinken.disk-sampler", qos: .utility)
    private var timer: DispatchSourceTimer?

    // Touched only on `queue`.
    private var tickCount: UInt64 = 0

    /// ~8.33 ms between ticks (120 Hz).
    private static let intervalNanos = 1_000_000_000 / DiskStatsAggregator.sampleHz
    /// ±2 ms jitter budget — the timer may coalesce within this rather than
    /// burst-sample to catch up (PRD §2.3, §5).
    private static let leewayNanos = 2_000_000

    init(aggregator: DiskStatsAggregator) {
        self.aggregator = aggregator
    }

    /// Starts the 120Hz sampling timer. Idempotent.
    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(),
                            repeating: .nanoseconds(Self.intervalNanos),
                            leeway: .nanoseconds(Self.leewayNanos))
            source.setEventHandler { [self] in tick() }
            timer = source
            source.resume()
            Log.sampling.debug("DiskStatsSampler started at \(DiskStatsAggregator.sampleHz, privacy: .public)Hz")
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
        // Monotonic clock — unaffected by wall-clock adjustments, so intervals
        // stay sane even across NTP steps or sleep/wake.
        let timestamp = ProcessInfo.processInfo.systemUptime
        let totals = Self.readPhysicalDiskTotals()
        tickCount &+= 1

        // 1 Hz heartbeat: lets the user confirm pipeline health from the console
        // (`log stream --predicate 'subsystem == "com.axiomic.blinken"' --level debug`,
        // or just Xcode's console) without flooding it at 120 Hz.
        if tickCount % UInt64(DiskStatsAggregator.sampleHz) == 0 {
            Log.sampling.debug("disk sample #\(self.tickCount, privacy: .public): read=\(totals.read, privacy: .public)B write=\(totals.written, privacy: .public)B")
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
