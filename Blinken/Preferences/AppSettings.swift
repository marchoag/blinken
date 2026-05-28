//
//  AppSettings.swift
//  Blinken
//
//  App-wide user preferences (LED color, glow intensity, launch-at-login),
//  persisted in UserDefaults and shared between the SwiftUI Settings pane and
//  the AppKit menu bar (PRD §1.5).
//

import SwiftUI
import AppKit
import ServiceManagement
import os

/// Shared, observable user settings.
///
/// Accessed only on the main thread — the Preferences UI and the 60Hz LED render
/// loop — so the singleton is `nonisolated(unsafe)`; there is no cross-thread use.
final class AppSettings: ObservableObject {

    nonisolated(unsafe) static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let glowIntensity = "glowIntensity"
        static let colorR = "ledColorR", colorG = "ledColorG", colorB = "ledColorB"
    }

    /// Classic HDD-LED red.
    static let defaultColor = Color(.sRGB, red: 0.88, green: 0.11, blue: 0.11)

    /// LED tint. Drives the menu bar lamp; persisted as sRGB components.
    @Published var ledColor: Color {
        didSet {
            ledNSColor = Self.nsColor(from: ledColor)
            persistColor()
        }
    }

    /// Bloom prominence, 0…1 (default 1). Scales the LED's soft glow.
    @Published var glowIntensity: Double {
        didSet { defaults.set(glowIntensity, forKey: Key.glowIntensity) }
    }

    /// Start Blinken automatically at login (managed by the system, not UserDefaults).
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    /// AppKit-side cached color for the LED renderer (avoids per-frame conversion).
    private(set) var ledNSColor: NSColor

    private init() {
        let r = defaults.object(forKey: Key.colorR) as? Double
        let g = defaults.object(forKey: Key.colorG) as? Double
        let b = defaults.object(forKey: Key.colorB) as? Double
        let color: Color = (r != nil && g != nil && b != nil)
            ? Color(.sRGB, red: r!, green: g!, blue: b!)
            : Self.defaultColor
        ledColor = color
        ledNSColor = Self.nsColor(from: color)
        glowIntensity = defaults.object(forKey: Key.glowIntensity) as? Double ?? 1.0
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    private func persistColor() {
        let ns = ledNSColor
        defaults.set(Double(ns.redComponent), forKey: Key.colorR)
        defaults.set(Double(ns.greenComponent), forKey: Key.colorG)
        defaults.set(Double(ns.blueComponent), forKey: Key.colorB)
    }

    private static func nsColor(from color: Color) -> NSColor {
        NSColor(color).usingColorSpace(.sRGB) ?? .systemRed
    }

    /// Register/unregister the login item. Failures (e.g. on an unsigned dev build)
    /// are logged, not fatal — the real distribution build registers cleanly.
    private func applyLaunchAtLogin() {
        do {
            switch (launchAtLogin, SMAppService.mainApp.status) {
            case (true, let s) where s != .enabled:   try SMAppService.mainApp.register()
            case (false, .enabled):                    try SMAppService.mainApp.unregister()
            default:                                    break
            }
        } catch {
            Log.menuBar.error("Launch-at-login update failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
