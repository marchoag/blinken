//
//  CounterStore.swift
//  Blinken
//
//  GRDB-backed SQLite persistence for the input odometer at
//  ~/Library/Application Support/Blinken/odometer.sqlite. Append-only events
//  plus denormalized totals; 1Hz batched flush (PRD §4.1, §4.2).
//

import Foundation
import GRDB

// TODO: Define the counter_events / counter_totals schema (migrations),
//       an increment(_:by:app:) API, and the 1Hz buffered flush.
