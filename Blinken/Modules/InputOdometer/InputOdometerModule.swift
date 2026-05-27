//
//  InputOdometerModule.swift
//  Blinken
//
//  v1.1 scaffolding: registered but isEnabled = false by default. When enabled
//  (via --enable-odometer-dev) it silently increments lifetime counters.
//  No menu surface, no preferences exposure in v1.0 (PRD §4).
//

import Foundation

// TODO: BlinkenModule conformer that, when enabled, drives PermissionCoordinator,
//       EventTapManager, and CounterStore — otherwise inert (no prompts, no tap).
