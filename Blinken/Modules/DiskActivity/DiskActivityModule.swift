//
//  DiskActivityModule.swift
//  Blinken
//
//  Disk Activity module entry point: owns the sampler, aggregator, and swap
//  monitor, and contributes the LED + swap bar to the menu bar (PRD §2.3).
//

import AppKit

// TODO: BlinkenModule conformer wiring DiskStatsSampler → DiskStatsAggregator,
//       plus SwapMonitor; exposes menuBarView and the disk/memory menu items.
