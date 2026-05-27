//
//  EventTapManager.swift
//  Blinken
//
//  Installs a CGEventTap at kCGSessionEventTap for key/click/scroll/move
//  events, feeding the CounterStore (PRD §4.1). v1.1 scaffolding.
//

import AppKit
import CoreGraphics

// TODO: Create/enable the CGEventTap, decode event types, and batch mouse-move
//       Euclidean distance (flush every 500ms) into the CounterStore.
