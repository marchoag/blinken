//
//  DiskStatsAggregatorTests.swift
//  BlinkenTests
//
//  Deterministic tests for DiskStatsAggregator against synthetic sample streams:
//  quiet, bursty, sustained, and pathological (counter rollover) inputs (PRD §6.1).
//

import XCTest
@testable import Blinken

// TODO: XCTestCase covering rolling P95, instantaneous rate, read/write split,
//       and counter-rollover handling with synthetic sample streams.
