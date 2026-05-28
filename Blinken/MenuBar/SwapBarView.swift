//
//  SwapBarView.swift
//  Blinken
//
//  Slim vertical swap-usage bar drawn to the right of the LED.
//  Fill = usedSwap / totalSwap; amber, shifting toward orange above 0.85 (PRD §1.3).
//

import AppKit

/// A slim vertical "fuel gauge" for swap usage. Fill height = `usedFraction`; the
/// fill color is the user's swap tint, lerping toward the PRD warning hue
/// (`#E07020`) once swap usage exceeds 85%.
final class SwapBarView: NSView {

    /// Fill fraction, clamped to [0, 1].
    var usedFraction: CGFloat = 0 {
        didSet {
            let clamped = max(0, min(1, usedFraction))
            if clamped != oldValue { needsDisplay = true }
        }
    }

    /// Base tint. Defaults to PRD amber `#D4A017`.
    var tintColor: NSColor = NSColor(srgbRed: 0.831, green: 0.627, blue: 0.090, alpha: 1.0) {
        didSet { if tintColor != oldValue { needsDisplay = true } }
    }

    /// Above this, the fill color lerps toward the warning hue (PRD §1.3).
    static let warningThreshold: CGFloat = 0.85

    /// PRD §1.3 warning color `#E07020`.
    private static let warnColor = NSColor(srgbRed: 0.878, green: 0.439, blue: 0.125, alpha: 1.0)

    // Pass clicks through to the hosting status button.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let frac = max(0, min(1, usedFraction))

        // PRD §1.1 geometry: ~4pt wide × 16pt tall, centered in the view.
        let barW: CGFloat = 4, barH: CGFloat = 16
        let rect = NSRect(
            x: (bounds.width - barW) / 2,
            y: (bounds.height - barH) / 2,
            width: barW,
            height: barH
        ).integral

        let tint = tintColor.usingColorSpace(.sRGB) ?? tintColor

        // Background: a dim tint slot so the bar is visible at 0% fill.
        NSColor(srgbRed: tint.redComponent * 0.18,
                green: tint.greenComponent * 0.18,
                blue: tint.blueComponent * 0.18,
                alpha: 1.0).setFill()
        NSBezierPath(rect: rect).fill()

        guard frac > 0 else { return }

        // Fill color lerps tint → warn above the threshold (smooth, not a hard flip).
        let shift = max(0, (frac - Self.warningThreshold) / (1 - Self.warningThreshold))
        let warn = Self.warnColor
        let fill = NSColor(
            srgbRed: tint.redComponent + (warn.redComponent - tint.redComponent) * shift,
            green: tint.greenComponent + (warn.greenComponent - tint.greenComponent) * shift,
            blue: tint.blueComponent + (warn.blueComponent - tint.blueComponent) * shift,
            alpha: 1.0
        )
        fill.setFill()
        let fillH = barH * frac
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY,
                                  width: rect.width, height: fillH).integral).fill()
    }
}
