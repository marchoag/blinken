//
//  DiskStatsAggregatorTests.swift
//  BlinkenTests
//
//  Deterministic tests for DiskStatsAggregator against synthetic sample streams:
//  quiet, bursty, sustained, and pathological (counter rollover) inputs (PRD §6.1).
//
//  These drive the aggregator directly with known (timestamp, bytesRead,
//  bytesWritten) tuples — no real IOKit — and assert on the published outputs.
//

import XCTest
@testable import Blinken

@MainActor
final class DiskStatsAggregatorTests: XCTestCase {

    // 120Hz cadence: one sample every 1/120 s (~8.33 ms).
    private let interval = 1.0 / 120.0
    private let mb = 1024.0 * 1024.0
    private let gb = 1024.0 * 1024.0 * 1024.0

    /// Feeds a run of cumulative samples into a fresh aggregator, starting from a
    /// baseline at t=0, where each tick adds `readPerTick(i)` / `writePerTick(i)`
    /// bytes to the running counters. Returns the aggregator after the final ingest.
    ///
    /// Counter arithmetic uses wrapping addition so callers can drive the UInt64
    /// counters across their rollover boundary.
    @discardableResult
    private func feed(
        count: Int,
        startRead: UInt64 = 0,
        startWrite: UInt64 = 0,
        readPerTick: (Int) -> UInt64,
        writePerTick: (Int) -> UInt64 = { _ in 0 }
    ) -> DiskStatsAggregator {
        let aggregator = DiskStatsAggregator()
        var read = startRead
        var write = startWrite
        // Baseline sample (i = 0): establishes the counters, emits no rate.
        aggregator.ingest(timestamp: 0, totalBytesRead: read, totalBytesWritten: write)
        for i in 1...count {
            read = read &+ readPerTick(i)
            write = write &+ writePerTick(i)
            aggregator.ingest(timestamp: Double(i) * interval,
                              totalBytesRead: read,
                              totalBytesWritten: write)
        }
        return aggregator
    }

    // MARK: - 1. Quiet stream

    /// Sustained low-rate I/O: instantaneous rate stays low, the rolling P95 sits
    /// at its floor (not spuriously elevated), and no spurious spikes appear.
    func testQuietStream() {
        // 120 KB/s: 1 KB per tick — far below the 10 MB/s P95 floor.
        let bytesPerTick: UInt64 = 1024
        let expectedRate = Double(bytesPerTick) / interval   // ~120 KB/s

        let aggregator = DiskStatsAggregator()
        var maxSeen = 0.0
        // Track the peak instantaneous rate across the whole run to prove there
        // are no spurious spikes — every tick carries the same tiny delta.
        var read: UInt64 = 0
        aggregator.ingest(timestamp: 0, totalBytesRead: 0, totalBytesWritten: 0)
        for i in 1...600 {
            read &+= bytesPerTick
            aggregator.ingest(timestamp: Double(i) * interval, totalBytesRead: read, totalBytesWritten: 0)
            maxSeen = max(maxSeen, aggregator.instantaneousRateBytesPerSec)
        }

        XCTAssertEqual(aggregator.instantaneousRateBytesPerSec, expectedRate, accuracy: expectedRate * 1e-6,
                       "Instantaneous rate should track the steady low input.")
        XCTAssertLessThan(maxSeen, mb,
                          "No tick should spike above 1 MB/s on a quiet stream.")
        XCTAssertEqual(aggregator.rolling60sP95, DiskStatsAggregator.p95FloorBytesPerSec, accuracy: 1.0,
                       "Quiet P95 should rest at the floor, not be spuriously elevated.")
    }

    // MARK: - 2. Bursty stream

    /// Mostly a moderate baseline with rare large spikes. The instantaneous rate
    /// reflects a spike when one lands, but the rolling P95 tracks the typical
    /// load — it must not be pegged to the burst maximum (spikes are <5% of
    /// samples, so they fall above the 95th percentile).
    func testBurstyStream() {
        let baselinePerTick: UInt64 = UInt64(20.0 * mb * interval)   // ~20 MB/s baseline
        let spikePerTick: UInt64 = UInt64(2.0 * gb * interval)       // ~2 GB/s spike
        let baselineRate = Double(baselinePerTick) / interval
        let spikeRate = Double(spikePerTick) / interval

        // 100 samples, 4 of them spikes (4%) — including the last so we can read
        // the instantaneous rate at a spike. 4% < 5% keeps spikes above the P95.
        let spikeTicks: Set<Int> = [23, 47, 71, 100]
        let aggregator = DiskStatsAggregator()
        var read: UInt64 = 0
        aggregator.ingest(timestamp: 0, totalBytesRead: 0, totalBytesWritten: 0)
        for i in 1...100 {
            read &+= spikeTicks.contains(i) ? spikePerTick : baselinePerTick
            aggregator.ingest(timestamp: Double(i) * interval, totalBytesRead: read, totalBytesWritten: 0)
        }

        // Last tick was a spike → instantaneous reflects it.
        XCTAssertEqual(aggregator.instantaneousRateBytesPerSec, spikeRate, accuracy: spikeRate * 1e-3,
                       "Instantaneous rate should reflect a spike when one lands.")
        // P95 should sit near the baseline, well below the burst max.
        XCTAssertEqual(aggregator.rolling60sP95, baselineRate, accuracy: baselineRate * 0.05,
                       "Rolling P95 should track the typical load, not the spike.")
        XCTAssertLessThan(aggregator.rolling60sP95, spikeRate / 10,
                          "Rolling P95 must not be pegged to the burst maximum.")
    }

    // MARK: - 3. Sustained heavy stream

    /// Consistent high throughput with both read and write activity. Instantaneous
    /// rate and rolling P95 are both elevated and roughly aligned, and the
    /// read/write split is reported separately.
    func testSustainedHeavyStream() {
        let readPerTick: UInt64 = UInt64(1.5 * gb * interval)   // ~1.5 GB/s read
        let writePerTick: UInt64 = UInt64(0.5 * gb * interval)  // ~0.5 GB/s write
        let expectedRead = Double(readPerTick) / interval
        let expectedWrite = Double(writePerTick) / interval
        let expectedTotal = expectedRead + expectedWrite

        let aggregator = feed(count: 300,
                              readPerTick: { _ in readPerTick },
                              writePerTick: { _ in writePerTick })

        XCTAssertEqual(aggregator.readRateBytesPerSec, expectedRead, accuracy: expectedRead * 1e-6,
                       "Read split should track sustained read throughput.")
        XCTAssertEqual(aggregator.writeRateBytesPerSec, expectedWrite, accuracy: expectedWrite * 1e-6,
                       "Write split should track sustained write throughput.")
        XCTAssertEqual(aggregator.instantaneousRateBytesPerSec, expectedTotal, accuracy: expectedTotal * 1e-6,
                       "Instantaneous total should be read + write.")
        // Instantaneous and rolling P95 should be elevated and roughly aligned.
        XCTAssertGreaterThan(aggregator.rolling60sP95, DiskStatsAggregator.p95FloorBytesPerSec,
                             "Sustained heavy load should push P95 well above the floor.")
        XCTAssertEqual(aggregator.rolling60sP95, expectedTotal, accuracy: expectedTotal * 0.01,
                       "Under steady load, P95 and instantaneous rate should align.")
    }

    // MARK: - 4. Counter rollover

    /// The underlying UInt64 byte counter wraps (max → 0) mid-stream while the
    /// true throughput stays steady. The wrap must produce a sane delta — no
    /// giant negative, no absurd-positive — matching the surrounding rate.
    func testCounterRollover() {
        let bytesPerTick: UInt64 = 1_000_000            // ~120 MB/s at 120Hz
        let expectedRate = Double(bytesPerTick) / interval

        // Start 1.5 ticks' worth of bytes below UInt64.max so the counter wraps
        // on the second post-baseline tick.
        let start = UInt64.max - 1_500_000
        let aggregator = DiskStatsAggregator()

        var read = start
        aggregator.ingest(timestamp: 0, totalBytesRead: read, totalBytesWritten: 0)

        // Tick 1: normal increment, no wrap yet.
        read &+= bytesPerTick                            // UInt64.max - 500_000
        aggregator.ingest(timestamp: 1 * interval, totalBytesRead: read, totalBytesWritten: 0)
        XCTAssertEqual(aggregator.instantaneousRateBytesPerSec, expectedRate, accuracy: expectedRate * 1e-6)

        // Tick 2: this increment crosses UInt64.max → wraps to a small value.
        read &+= bytesPerTick                            // wraps to 499_999
        XCTAssertLessThan(read, start, "Counter must have wrapped for this test to be meaningful.")
        aggregator.ingest(timestamp: 2 * interval, totalBytesRead: read, totalBytesWritten: 0)

        // The wrap delta must equal the steady transfer — not negative, not absurd.
        let wrapRate = aggregator.instantaneousRateBytesPerSec
        XCTAssertGreaterThanOrEqual(wrapRate, 0, "Wrap must never produce a negative rate.")
        XCTAssertLessThan(wrapRate, DiskStatsAggregator.maxPlausibleBytesPerSec,
                          "Wrap must never produce an absurd-positive rate.")
        XCTAssertEqual(wrapRate, expectedRate, accuracy: expectedRate * 1e-6,
                       "Rate across the wrap should match the steady throughput.")

        // Ticks 3–4: continue post-wrap, still steady.
        for i in 3...4 {
            read &+= bytesPerTick
            aggregator.ingest(timestamp: Double(i) * interval, totalBytesRead: read, totalBytesWritten: 0)
            XCTAssertEqual(aggregator.instantaneousRateBytesPerSec, expectedRate, accuracy: expectedRate * 1e-6)
        }

        // A genuine counter reset (tiny value from a far-from-max prior) is not a
        // wrap; the guard must suppress it rather than emit a near-UInt64.max rate.
        aggregator.ingest(timestamp: 5 * interval, totalBytesRead: 0, totalBytesWritten: 0)
        XCTAssertGreaterThanOrEqual(aggregator.instantaneousRateBytesPerSec, 0)
        XCTAssertLessThan(aggregator.instantaneousRateBytesPerSec, DiskStatsAggregator.maxPlausibleBytesPerSec,
                          "A counter reset must not be reported as an absurd spike.")
    }

    // MARK: - 5. Menu figures: cumulative totals + smoothed rate

    /// The menu shows cumulative totals (odometer) + a smoothed rate. Totals must
    /// track the latest raw counter and never drop while idle; the smoothed rate
    /// converges under sustained load and decays toward 0 after sustained idle.
    func testCumulativeTotalsAndSmoothedRate() {
        let perTick: UInt64 = 1_000_000              // ~120 MB/s at 120Hz
        let expectedRate = Double(perTick) / interval

        let aggregator = DiskStatsAggregator()
        var read: UInt64 = 0
        aggregator.ingest(timestamp: 0, totalBytesRead: 0, totalBytesWritten: 0)

        // Sustained read for ~5s (>> 1s EMA time constant) → smoothed converges.
        for i in 1...600 {
            read &+= perTick
            aggregator.ingest(timestamp: Double(i) * interval, totalBytesRead: read, totalBytesWritten: 0)
        }
        XCTAssertEqual(aggregator.totalBytesRead, read,
                       "Cumulative total should equal the latest raw counter reading.")
        XCTAssertEqual(aggregator.smoothedReadRateBytesPerSec, expectedRate, accuracy: expectedRate * 0.05,
                       "Smoothed read rate should converge to the sustained throughput.")

        // Now go idle for ~5s (counter unchanged) → smoothed decays, total holds.
        let totalAfterActive = read
        for i in 601...1200 {
            aggregator.ingest(timestamp: Double(i) * interval, totalBytesRead: read, totalBytesWritten: 0)
        }
        XCTAssertEqual(aggregator.totalBytesRead, totalAfterActive,
                       "Cumulative total must not reset/drop while idle (only on restart).")
        XCTAssertLessThan(aggregator.smoothedReadRateBytesPerSec, expectedRate * 0.05,
                          "Smoothed rate should decay toward 0 after sustained idle.")
    }
}
