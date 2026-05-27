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

// TODO: Ring buffer + per-sample computation of instantaneousRateBytesPerSec,
//       rolling60sP95 (floor 10 MB/s), and separate read/write rates,
//       exposed as @Published properties.
