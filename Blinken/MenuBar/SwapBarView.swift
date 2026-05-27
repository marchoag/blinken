//
//  SwapBarView.swift
//  Blinken
//
//  Custom NSView drawing the slim vertical swap-usage bar to the right of the LED.
//  Fill = usedSwap / totalSwap; amber, shifting to orange above 0.85 (PRD §1.3).
//

import AppKit

// TODO: NSView subclass rendering the swap fill bar (≈4×16pt).
//       #D4A017 normal, #E07020 when usedSwap/totalSwap > 0.85.
