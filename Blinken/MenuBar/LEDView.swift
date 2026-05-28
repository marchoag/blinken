//
//  LEDView.swift
//  Blinken
//
//  Custom NSView drawing the HDD activity LED — a radial gradient whose
//  brightness tracks instantaneous disk throughput, redrawn at 60Hz (PRD §1.2).
//

import AppKit

/// A circular "LED" that glows in proportion to `brightness` (0.04…1.0), in the
/// user's chosen `tintColor`. Drawn as a near-black bezel ring around a
/// radial-gradient face (bright core → dark edge) with a soft outer bloom and a
/// specular highlight, so it reads as a lit lamp on light and dark menu bars and
/// never goes fully black when idle.
final class LEDView: NSView {

    /// Lit fraction, clamped to [`Self.minBrightness`, 1.0]. Setting it redraws.
    var brightness: CGFloat = LEDView.minBrightness {
        didSet {
            let clamped = max(Self.minBrightness, min(1.0, brightness))
            if clamped != oldValue { needsDisplay = true }
        }
    }

    /// Base LED color (user preference). Defaults to classic HDD red.
    var tintColor: NSColor = NSColor(srgbRed: 0.88, green: 0.11, blue: 0.11, alpha: 1.0) {
        didSet { if tintColor != oldValue { needsDisplay = true } }
    }

    /// Soft-glow prominence multiplier, 0…1 (user preference).
    var glowIntensity: CGFloat = 1.0 {
        didSet { if glowIntensity != oldValue { needsDisplay = true } }
    }

    /// Faintly-visible floor — confirms the app is running even at zero I/O (PRD §1.2).
    static let minBrightness: CGFloat = 0.04

    /// LED diameter in logical points (PRD §1.1: ~14×14).
    private static let diameter: CGFloat = 14

    // Status-bar overlay: let clicks fall through to the hosting status button.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let b = max(Self.minBrightness, min(1.0, brightness))
        let tint = tintColor.usingColorSpace(.sRGB) ?? tintColor
        let r = tint.redComponent, g = tint.greenComponent, bl = tint.blueComponent
        let center = NSPoint(x: bounds.midX, y: bounds.midY)

        // 1. Soft outer glow — a radial bloom that grows with activity. Nearly
        //    invisible at idle, it blooms during bursts so a "blink" reads as a
        //    soft glow rather than a hard on/off.
        let glowAlpha = 0.6 * b * max(0, min(1, glowIntensity))
        if glowAlpha > 0.002 {
            let d = min(bounds.width, bounds.height) - 1
            let glowRect = NSRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
            let glowColor = NSColor(srgbRed: r, green: g, blue: bl, alpha: glowAlpha)
            if let glow = NSGradient(colors: [glowColor, glowColor.withAlphaComponent(0)],
                                     atLocations: [0.0, 1.0], colorSpace: .sRGB) {
                glow.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)
            }
        }

        // 2. LED body.
        let rect = NSRect(
            x: (center.x - Self.diameter / 2).rounded(),
            y: (center.y - Self.diameter / 2).rounded(),
            width: Self.diameter,
            height: Self.diameter)

        // Bezel: a dim, near-black tint ring so the lamp reads as "present but
        // unlit" at rest and stays visible against a light menu bar.
        NSColor(srgbRed: r * 0.09, green: g * 0.09, blue: bl * 0.09, alpha: 1.0).setFill()
        NSBezierPath(ovalIn: rect).fill()

        // Face: radial gradient, bright core → dark edge, intensity scaled by `b`.
        let face = rect.insetBy(dx: 1.5, dy: 1.5)
        let core = NSColor(srgbRed: r * b, green: g * b, blue: bl * b, alpha: 1.0)
        let edge = NSColor(srgbRed: r * 0.38 * b, green: g * 0.38 * b, blue: bl * 0.38 * b, alpha: 1.0)
        if let gradient = NSGradient(starting: core, ending: edge) {
            // Highlight sits slightly above center for a glassy, domed look.
            gradient.draw(in: NSBezierPath(ovalIn: face), relativeCenterPosition: NSPoint(x: 0, y: 0.22))
        } else {
            core.setFill()
            NSBezierPath(ovalIn: face).fill()
        }

        // 3. Specular highlight — a soft near-white spot near the top for a domed,
        //    glassy lamp look; fades in with brightness.
        let hi = face.insetBy(dx: face.width * 0.28, dy: face.height * 0.28)
                     .offsetBy(dx: 0, dy: face.height * 0.18)
        NSColor(srgbRed: min(1, r + 0.4), green: min(1, g + 0.4), blue: min(1, bl + 0.4), alpha: 0.35 * b).setFill()
        NSBezierPath(ovalIn: hi).fill()
    }
}
