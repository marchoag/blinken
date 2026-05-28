//
//  DiskStatsAggregator.swift
//  Blinken
//
//  Maintains a 7,200-sample ring buffer (60s × 120Hz) and computes the
//  instantaneous rate, rolling 60s P95 ceiling, and read/write split.
//  Publishes via Combine for the views to observe (PRD §2.3).
//

import Foundation
import Combine

/// Turns the sampler's cumulative byte counters into the rate signals the UI
/// renders. Fed one `(timestamp, totalBytesRead, totalBytesWritten)` tuple per
/// 120Hz tick; publishes the latest instantaneous rate, the rolling 60s P95
/// (the LED-brightness normalization ceiling), and the read/write split.
///
/// Main-actor isolated: the sampler computes byte totals off the main thread,
/// then hops here to ingest, so all `@Published` mutation happens on main where
/// SwiftUI observes it.
@MainActor
final class DiskStatsAggregator: ObservableObject {

    // MARK: - Configuration (PRD §2.3)

    // These are immutable cadence/threshold constants read by the (nonisolated)
    // sampler as well as the aggregator, so they're explicitly `nonisolated`.

    /// Disk sampling cadence.
    nonisolated static let sampleHz = 120
    /// Rolling window length for the P95 ceiling.
    nonisolated static let windowSeconds = 60
    /// Ring-buffer capacity: 60 seconds × 120 Hz.
    nonisolated static let windowCapacity = sampleHz * windowSeconds

    /// Floor for the rolling P95 ceiling. During quiet periods the real P95
    /// collapses toward zero; without a floor the LED brightness (throughput ÷
    /// P95) would peg bright on trivial background I/O. 10 MB/s keeps idle dim.
    nonisolated static let p95FloorBytesPerSec: Double = 10 * 1024 * 1024

    /// A per-sample delta implying a rate above this is treated as a counter
    /// reset or multi-wrap and dropped, rather than published as a bogus spike.
    /// 64 GB/s sits far above any real NVMe (~7 GB/s) yet far below the
    /// near-UInt64.max delta a naive reset would produce.
    nonisolated static let maxPlausibleBytesPerSec: Double = 64 * 1024 * 1024 * 1024

    // MARK: - Published outputs (observed by the views)

    /// Total (read + write) throughput over the most recent sample interval.
    @Published private(set) var instantaneousRateBytesPerSec: Double = 0
    /// 95th percentile of total throughput over the last 60s, floored at
    /// `p95FloorBytesPerSec`. Used as the LED-brightness normalization ceiling.
    @Published private(set) var rolling60sP95: Double = DiskStatsAggregator.p95FloorBytesPerSec
    /// Latest read-only throughput (for the dropdown menu split).
    @Published private(set) var readRateBytesPerSec: Double = 0
    /// Latest write-only throughput (for the dropdown menu split).
    @Published private(set) var writeRateBytesPerSec: Double = 0

    /// ~1s-smoothed read throughput for the menu — steady, non-flickering.
    @Published private(set) var smoothedReadRateBytesPerSec: Double = 0
    /// ~1s-smoothed write throughput for the menu.
    @Published private(set) var smoothedWriteRateBytesPerSec: Double = 0

    /// Cumulative bytes read — the latest raw IOKit counter (the same figure the OS
    /// and Activity Monitor report). Monotonic; only resets on restart. Menu odometer.
    @Published private(set) var totalBytesRead: UInt64 = 0
    /// Cumulative bytes written — the latest raw IOKit counter.
    @Published private(set) var totalBytesWritten: UInt64 = 0

    /// EMA time constant (seconds) for the smoothed menu rates.
    nonisolated static let menuRateTimeConstant: Double = 1.0

    // MARK: - Ring buffer (per-sample total throughput, bytes/sec)

    private var ring = [Double](repeating: 0, count: DiskStatsAggregator.windowCapacity)
    private var ringCount = 0   // number of valid entries (≤ capacity)
    private var ringHead = 0    // next write index

    // MARK: - Previous cumulative counters

    private var hasPrevious = false
    private var prevTimestamp: Double = 0
    private var prevBytesRead: UInt64 = 0
    private var prevBytesWritten: UInt64 = 0

    // MARK: - Ingest

    /// Feed one cumulative sample. `totalBytesRead` / `totalBytesWritten` are the
    /// device byte counters at `timestamp` (seconds) — monotonically increasing,
    /// subject to UInt64 wraparound. The first sample only sets a baseline.
    func ingest(timestamp: Double, totalBytesRead: UInt64, totalBytesWritten: UInt64) {
        // Cumulative totals always reflect the latest raw counters (the menu's
        // odometer figures) — even on the first sample, and even while idle.
        self.totalBytesRead = totalBytesRead
        self.totalBytesWritten = totalBytesWritten

        defer {
            prevTimestamp = timestamp
            prevBytesRead = totalBytesRead
            prevBytesWritten = totalBytesWritten
            hasPrevious = true
        }

        // No rate can be computed without a prior point.
        guard hasPrevious else { return }

        let interval = timestamp - prevTimestamp
        // Drop duplicate / out-of-order timestamps rather than divide by ≤ 0.
        guard interval > 0 else { return }

        let readDelta = Self.delta(previous: prevBytesRead, current: totalBytesRead, interval: interval)
        let writeDelta = Self.delta(previous: prevBytesWritten, current: totalBytesWritten, interval: interval)

        let readRate = Double(readDelta) / interval
        let writeRate = Double(writeDelta) / interval
        let totalRate = readRate + writeRate

        readRateBytesPerSec = readRate
        writeRateBytesPerSec = writeRate
        instantaneousRateBytesPerSec = totalRate

        // ~1s EMA for the menu's read/write figures. The raw per-tick rate is far
        // too clumpy to read as a number — it hits 0 between bursts even during an
        // active copy — so we smooth it into a steady "current throughput" that only
        // falls to 0 after sustained idle. (The LED keeps the twitchy instantaneous
        // rate; that flicker is the intended aesthetic.)
        let alpha = 1 - exp(-interval / Self.menuRateTimeConstant)
        smoothedReadRateBytesPerSec += alpha * (readRate - smoothedReadRateBytesPerSec)
        smoothedWriteRateBytesPerSec += alpha * (writeRate - smoothedWriteRateBytesPerSec)

        appendToRing(totalRate)
        rolling60sP95 = max(percentile95(), Self.p95FloorBytesPerSec)
    }

    // MARK: - Delta with rollover / reset handling

    /// Bytes transferred between two cumulative counter readings.
    ///
    /// - Normal: `current >= previous` → simple difference.
    /// - Counter wrap (UInt64 max → 0): wrapping subtraction `current &- previous`
    ///   yields *exactly* the transferred bytes for a single 64-bit wrap, so a wrap
    ///   produces a sane delta rather than a giant negative.
    /// - Reset / multi-wrap: a delta implying an impossible rate is treated as 0,
    ///   so we never publish an absurd-positive spike.
    private static func delta(previous: UInt64, current: UInt64, interval: Double) -> UInt64 {
        let raw = current >= previous ? current - previous : current &- previous
        let impliedRate = Double(raw) / interval
        return impliedRate <= maxPlausibleBytesPerSec ? raw : 0
    }

    // MARK: - Ring buffer helpers

    private func appendToRing(_ value: Double) {
        ring[ringHead] = value
        ringHead = (ringHead + 1) % Self.windowCapacity
        if ringCount < Self.windowCapacity { ringCount += 1 }
    }

    /// Nearest-rank 95th percentile of the valid ring contents (0 when empty).
    /// The valid entries are `ring[0..<ringCount]` before the buffer wraps and
    /// the whole array after; order is irrelevant since we sort.
    private func percentile95() -> Double {
        guard ringCount > 0 else { return 0 }
        let sorted = ring.prefix(ringCount).sorted()
        let rank = Int((0.95 * Double(ringCount)).rounded(.up))   // 1-based
        let index = min(max(rank - 1, 0), ringCount - 1)
        return sorted[index]
    }
}
