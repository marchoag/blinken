//
//  LEDView.swift
//  Blinken
//
//  Custom NSView drawing the HDD activity LED — a radial gradient whose
//  brightness tracks instantaneous disk throughput, redrawn at 60Hz (PRD §1.2).
//

import AppKit

/// A circular "LED" that glows in proportion to `brightness` (0.04…1.0), in the
/// user's chosen `tintColor`. A near-black bezel rings a radial-gradient face
/// (bright core → dark edge); above ~55% brightness the core goes "white-hot" and
/// a soft outer bloom ramps up hard, so heavy I/O reads as a really bright glow.
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
        let gi = max(0, min(1, glowIntensity))

        // "Hotness" ramps in above ~55% brightness, peaking at 1.0 — it drives both
        // the bright bloom and the white-hot core so 80%+ I/O really pops.
        let hot = pow(max(0, (b - 0.55) / 0.45), 1.6)

        // 1. Soft outer glow. Alpha ramps steeply via `hot` so the top end blooms.
        let glowAlpha = min(1.0, (0.30 * b + 0.70 * hot) * gi)
        if glowAlpha > 0.002 {
            let d = (min(bounds.width, bounds.height) - 1) * (0.9 + 0.1 * hot)
            let glowRect = NSRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
            // Saturated tint — no white mixing — so the halo reads as vivid red
            // (or whatever tint) instead of pastel pink at high brightness.
            let glowColor = NSColor(srgbRed: r, green: g, blue: bl, alpha: glowAlpha)
            if let glow = NSGradient(colors: [glowColor, glowColor.withAlphaComponent(0)],
                                     atLocations: [0.0, 1.0], colorSpace: .sRGB) {
                glow.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)
            }
        }

        // 2. LED face: radial gradient (bright core → dark edge). The core scales
        //    with `b`, then lightens toward white as it gets hot (a filament
        //    glowing up). No separate bezel — the gradient's own dark edge is the
        //    rim, so the outer glow flows continuously into the lamp without a
        //    black "ring" interrupting it.
        let face = NSRect(
            x: (center.x - Self.diameter / 2).rounded(),
            y: (center.y - Self.diameter / 2).rounded(),
            width: Self.diameter,
            height: Self.diameter)
        // Saturated tint scaled by brightness — the lamp stays vivid; the specular
        // highlight below provides the "lit" cue without desaturating the body.
        let core = NSColor(srgbRed: r * b, green: g * b, blue: bl * b, alpha: 1.0)
        let edge = NSColor(srgbRed: r * 0.4 * b, green: g * 0.4 * b, blue: bl * 0.4 * b, alpha: 1.0)
        if let gradient = NSGradient(starting: core, ending: edge) {
            gradient.draw(in: NSBezierPath(ovalIn: face), relativeCenterPosition: NSPoint(x: 0, y: 0.22))
        } else {
            core.setFill()
            NSBezierPath(ovalIn: face).fill()
        }

        // 3. Specular highlight — a small glassy glint near the top. Kept tight +
        //    low alpha so it gives a "lit lamp" cue without washing the body into
        //    pastel.
        let hi = face.insetBy(dx: face.width * 0.35, dy: face.height * 0.35)
                     .offsetBy(dx: 0, dy: face.height * 0.18)
        NSColor(white: 1.0, alpha: 0.30 * b).setFill()
        NSBezierPath(ovalIn: hi).fill()
    }
}
