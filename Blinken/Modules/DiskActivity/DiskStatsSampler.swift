//
//  DiskStatsSampler.swift
//  Blinken
//
//  Polls IOKit IOBlockStorageDriver statistics at 120Hz, summing bytes
//  read/written across physical devices only (PRD §2.3).
//

import Foundation
import IOKit

// TODO: On each 120Hz tick, enumerate IOBlockStorageDriver entries via
//       IOServiceGetMatchingServices, read the Statistics dict, filter to
//       physical devices (dedupe by BSD name), and emit
//       (timestamp, totalBytesRead, totalBytesWritten) to the aggregator.
