//
//  DiskActivityModule.swift
//  Blinken
//
//  Disk Activity module entry point: owns the sampler, aggregator, and swap
//  monitor, and contributes the LED + swap bar to the menu bar (PRD §2.3).
//

import Foundation

/// Owns the disk sampling pipeline. Phase 2 wires the sampler → aggregator only;
/// the swap monitor, menu-bar contribution, and `BlinkenModule` conformance land
/// with the UI / module-system phase.
///
/// Main-actor isolated because it holds the (main-actor) `DiskStatsAggregator`,
/// which the views observe.
@MainActor
final class DiskActivityModule {

    /// Published rate signals for the views to observe.
    let aggregator = DiskStatsAggregator()

    /// Published swap and memory-pressure state for the views to observe.
    let swap = SwapMonitor()

    private lazy var sampler = DiskStatsSampler(aggregator: aggregator)

    /// Begins 120Hz disk sampling and 1Hz swap/pressure polling.
    func start() {
        sampler.start()
        swap.start()
    }

    /// Stops disk sampling and swap polling.
    func stop() {
        sampler.stop()
        swap.stop()
    }
}
