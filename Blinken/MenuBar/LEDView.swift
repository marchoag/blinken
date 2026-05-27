//
//  LEDView.swift
//  Blinken
//
//  Custom NSView drawing the HDD activity LED — a red radial gradient whose
//  brightness tracks instantaneous disk throughput, redrawn at 60Hz (PRD §1.2).
//

import AppKit

// TODO: NSView subclass that renders the LED radial gradient.
//       Brightness in [MIN_BRIGHTNESS, 1.0]; exact RGBA values TBD (PRD §8 open question).
