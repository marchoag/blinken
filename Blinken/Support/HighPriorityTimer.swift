//
//  HighPriorityTimer.swift
//  Blinken
//
//  DispatchSourceTimer wrapper for the 120Hz disk sampling cadence on a
//  dedicated QoS .utility queue, with ±2ms jitter tolerance (PRD §2.3, §5).
//

import Foundation

// TODO: Wrap a DispatchSourceTimer (leeway-bounded) that fires ~every 8.33ms
//       and drops — rather than catches up — samples beyond the jitter budget.
