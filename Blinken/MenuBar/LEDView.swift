//
//  LEDView.swift
//  Blinken
//
//  Custom NSView drawing the HDD activity LED — a red radial gradient whose
//  brightness tracks instantaneous disk throughput, redrawn at 60Hz (PRD §1.2).
//

import AppKit

/// A circular red "LED" that glows in proportion to `brightness` (0.04…1.0).
/// Drawn as a near-black bezel ring around a radial-gradient face — a bright,
/// slightly-offset core fading to a dark red edge — so it reads as a lit lamp
/// on both light and dark menu bars and never goes fully black when idle.
final class LEDView: NSView {

    /// Lit fraction, clamped to [`Self.minBrightness`, 1.0]. Setting it redraws.
    var brightness: CGFloat = LEDView.minBrightness {
        didSet {
            let clamped = max(Self.minBrightness, min(1.0, brightness))
            if clamped != oldValue { needsDisplay = true }
        }
    }

    /// Faintly-visible floor — confirms the app is running even at zero I/O (PRD §1.2).
    static let minBrightness: CGFloat = 0.04

    /// LED diameter in logical points (PRD §1.1: ~14×14).
    private static let diameter: CGFloat = 14

    // Status-bar overlay: let clicks fall through to the hosting status button.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let b = max(Self.minBrightness, min(1.0, brightness))

        let rect = NSRect(
            x: ((bounds.width - Self.diameter) / 2).rounded(),
            y: ((bounds.height - Self.diameter) / 2).rounded(),
            width: Self.diameter,
            height: Self.diameter)

        // Bezel: a dim, near-black red ring so the lamp reads as "present but unlit"
        // at rest and stays visible against a light menu bar.
        NSColor(srgbRed: 0.07, green: 0.0, blue: 0.0, alpha: 1.0).setFill()
        NSBezierPath(ovalIn: rect).fill()

        // Face: radial gradient, bright core → dark edge, intensity scaled by `b`.
        let face = rect.insetBy(dx: 1.5, dy: 1.5)
        let core = NSColor(srgbRed: b, green: 0.12 * b, blue: 0.10 * b, alpha: 1.0)
        let edge = NSColor(srgbRed: 0.40 * b, green: 0.0, blue: 0.0, alpha: 1.0)
        if let gradient = NSGradient(starting: core, ending: edge) {
            // Highlight sits slightly above center for a glassy, domed look.
            gradient.draw(in: NSBezierPath(ovalIn: face), relativeCenterPosition: NSPoint(x: 0, y: 0.25))
        } else {
            core.setFill()
            NSBezierPath(ovalIn: face).fill()
        }
    }
}
