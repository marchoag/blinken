//
//  Logger.swift
//  Blinken
//
//  Thin wrapper around os.Logger with per-subsystem categories.
//

import os

/// Centralized `os.Logger` factory. Categories let Console.app / `log stream`
/// filter Blinken's output by area (e.g. `subsystem:com.axiomic.blinken
/// category:sampling`). `os.Logger` is `Sendable`, so these are safe to read
/// from any actor or background queue.
enum Log {
    private static let subsystem = "com.axiomic.blinken"

    /// Disk sampling pipeline (DiskStatsSampler / DiskStatsAggregator).
    static let sampling = Logger(subsystem: subsystem, category: "sampling")

    /// Menu bar rendering and status item lifecycle.
    static let menuBar = Logger(subsystem: subsystem, category: "menubar")

    /// Input Odometer module (v1.1 scaffold).
    static let odometer = Logger(subsystem: subsystem, category: "odometer")
}
