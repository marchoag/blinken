//
//  AppSettings.swift
//  Blinken
//
//  App-wide user preferences (LED color, glow intensity, swap-bar color,
//  launch-at-login), persisted in UserDefaults and shared between the SwiftUI
//  Settings pane and the AppKit menu bar (PRD §1.5).
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
        static let ledR = "ledColorR", ledG = "ledColorG", ledB = "ledColorB"
        static let swapR = "swapColorR", swapG = "swapColorG", swapB = "swapColorB"
    }

    /// Classic HDD-LED red.
    static let defaultLEDColor = Color(.sRGB, red: 0.88, green: 0.11, blue: 0.11)
    /// Muted amber (#D4A017) per PRD §1.3.
    static let defaultSwapColor = Color(.sRGB, red: 0.831, green: 0.627, blue: 0.090)

    /// LED tint. Drives the menu bar lamp; persisted as sRGB components.
    @Published var ledColor: Color {
        didSet { ledNSColor = Self.nsColor(from: ledColor); persist(ledColor, Key.ledR, Key.ledG, Key.ledB) }
    }

    /// Swap-bar tint (used once the swap bar lands).
    @Published var swapColor: Color {
        didSet { swapNSColor = Self.nsColor(from: swapColor); persist(swapColor, Key.swapR, Key.swapG, Key.swapB) }
    }

    /// Bloom prominence, 0…1 (default 1). Scales the LED's soft glow.
    @Published var glowIntensity: Double {
        didSet { defaults.set(glowIntensity, forKey: Key.glowIntensity) }
    }

    /// Start Blinken automatically at login (managed by the system, not UserDefaults).
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    /// AppKit-side cached colors for the renderers (avoid per-frame conversion).
    private(set) var ledNSColor: NSColor
    private(set) var swapNSColor: NSColor

    private init() {
        let led = Self.loadColor(Key.ledR, Key.ledG, Key.ledB, default: Self.defaultLEDColor)
        let swap = Self.loadColor(Key.swapR, Key.swapG, Key.swapB, default: Self.defaultSwapColor)
        ledColor = led
        swapColor = swap
        ledNSColor = Self.nsColor(from: led)
        swapNSColor = Self.nsColor(from: swap)
        glowIntensity = defaults.object(forKey: Key.glowIntensity) as? Double ?? 1.0
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    private static func loadColor(_ rKey: String, _ gKey: String, _ bKey: String, default fallback: Color) -> Color {
        let d = UserDefaults.standard
        guard let r = d.object(forKey: rKey) as? Double,
              let g = d.object(forKey: gKey) as? Double,
              let b = d.object(forKey: bKey) as? Double else { return fallback }
        return Color(.sRGB, red: r, green: g, blue: b)
    }

    private func persist(_ color: Color, _ rKey: String, _ gKey: String, _ bKey: String) {
        let ns = Self.nsColor(from: color)
        defaults.set(Double(ns.redComponent), forKey: rKey)
        defaults.set(Double(ns.greenComponent), forKey: gKey)
        defaults.set(Double(ns.blueComponent), forKey: bKey)
    }

    private static func nsColor(from color: Color) -> NSColor {
        NSColor(color).usingColorSpace(.sRGB) ?? .systemRed
    }

    /// Restore the visual prefs to factory defaults (LED color, swap color, glow).
    /// Leaves launch-at-login alone — that's a user/system choice, not appearance.
    func resetAppearanceToDefaults() {
        ledColor = Self.defaultLEDColor
        swapColor = Self.defaultSwapColor
        glowIntensity = 1.0
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
