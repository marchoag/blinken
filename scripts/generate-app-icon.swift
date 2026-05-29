#!/usr/bin/env swift
//
// scripts/generate-app-icon.swift
//
// Renders Blinken's app icon (a glowing red LED on warm cream paper) to a
// 1024×1024 master PNG using Core Graphics. The design matches the website's
// hero LED: paper background, multi-stop radial gradient lamp, soft outer
// halo, small specular highlight.
//
// Run from the repo root:
//     swift scripts/generate-app-icon.swift
//
// Output: AppIcon-1024.png in the current directory.
//

import AppKit
import CoreGraphics

let canvas: CGFloat = 1024
let pixelSize = Int(canvas)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 32)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// 1. Warm-cream paper background (matches website #FAF7EE).
NSColor(srgbRed: 0.980, green: 0.969, blue: 0.933, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvas, height: canvas)).fill()

let center = CGPoint(x: canvas / 2, y: canvas / 2)
let space = CGColorSpaceCreateDeviceRGB()

// 2. Soft outer glow halo — saturated red fading to transparent.
let glow = CGGradient(
    colorsSpace: space,
    colors: [
        NSColor(srgbRed: 0.882, green: 0.110, blue: 0.110, alpha: 0.55).cgColor,
        NSColor(srgbRed: 0.882, green: 0.110, blue: 0.110, alpha: 0.18).cgColor,
        NSColor(srgbRed: 0.882, green: 0.110, blue: 0.110, alpha: 0.00).cgColor,
    ] as CFArray,
    locations: [0.0, 0.55, 1.0])!
ctx.drawRadialGradient(
    glow,
    startCenter: center, startRadius: 0,
    endCenter: center, endRadius: 480,
    options: [])

// 3. LED body — multi-stop radial gradient clipped to a circle.
ctx.saveGState()
let ledDiameter: CGFloat = 560
let ledRect = NSRect(
    x: (canvas - ledDiameter) / 2,
    y: (canvas - ledDiameter) / 2,
    width: ledDiameter, height: ledDiameter)
NSBezierPath(ovalIn: ledRect).addClip()

let lamp = CGGradient(
    colorsSpace: space,
    colors: [
        NSColor(srgbRed: 1.000, green: 0.961, blue: 0.929, alpha: 1).cgColor,  // hot core (near-white)
        NSColor(srgbRed: 1.000, green: 0.706, blue: 0.600, alpha: 1).cgColor,  // warm transition
        NSColor(srgbRed: 1.000, green: 0.322, blue: 0.224, alpha: 1).cgColor,  // orange-red
        NSColor(srgbRed: 0.882, green: 0.110, blue: 0.110, alpha: 1).cgColor,  // main red
        NSColor(srgbRed: 0.541, green: 0.031, blue: 0.031, alpha: 1).cgColor,  // dark
        NSColor(srgbRed: 0.184, green: 0.012, blue: 0.012, alpha: 1).cgColor,  // shadow rim
    ] as CFArray,
    locations: [0.00, 0.08, 0.20, 0.40, 0.78, 1.00])!

// Gradient center offset up (38% from the top, like the website LED).
let lampCenterY = ledRect.minY + ledRect.height * 0.62
ctx.drawRadialGradient(
    lamp,
    startCenter: CGPoint(x: ledRect.midX, y: lampCenterY), startRadius: 0,
    endCenter: CGPoint(x: ledRect.midX, y: ledRect.midY), endRadius: ledRect.width / 2,
    options: [])

ctx.restoreGState()

// 4. Soft specular highlight near the top — sells the "glassy dome" cue.
let highlightCenter = CGPoint(x: ledRect.midX, y: ledRect.minY + ledRect.height * 0.76)
let highlight = CGGradient(
    colorsSpace: space,
    colors: [
        NSColor(white: 1.0, alpha: 0.55).cgColor,
        NSColor(white: 1.0, alpha: 0.00).cgColor,
    ] as CFArray,
    locations: [0.0, 1.0])!
ctx.drawRadialGradient(
    highlight,
    startCenter: highlightCenter, startRadius: 0,
    endCenter: highlightCenter, endRadius: 130,
    options: [])

NSGraphicsContext.restoreGraphicsState()

// Save as PNG.
let outURL = URL(fileURLWithPath: "AppIcon-1024.png")
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    print("ERROR: could not encode PNG")
    exit(1)
}
try pngData.write(to: outURL)
print("Wrote \(outURL.path)")
