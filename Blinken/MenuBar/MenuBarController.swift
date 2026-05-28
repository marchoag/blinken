//
//  MenuBarController.swift
//  Blinken
//
//  Orchestrates the NSStatusItem: hosts the composite LED + swap bar view
//  and attaches the dropdown StatusMenu (PRD §1.1, §2.2).
//

import AppKit
import SwiftUI

/// Owns the menu bar status item: hosts the `LEDView`, drives its brightness from
/// the `DiskStatsAggregator` on a ~60Hz render loop, and presents the dropdown.
///
/// Phase 3 wires the LED + a minimal disk-activity menu; the swap bar and the
/// memory section land with the SwapMonitor phase.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private let aggregator: DiskStatsAggregator
    private let statusItem: NSStatusItem
    private let ledView: LEDView

    private var renderTimer: Timer?
    private var menuRefreshTimer: Timer?
    private var preferencesWindow: NSWindow?

    private let readItem = NSMenuItem(title: "Read:  —", action: nil, keyEquivalent: "")
    private let writeItem = NSMenuItem(title: "Write:  —", action: nil, keyEquivalent: "")

    init(aggregator: DiskStatsAggregator) {
        self.aggregator = aggregator
        self.statusItem = NSStatusBar.system.statusItem(withLength: 24)
        let thickness = NSStatusBar.system.thickness
        self.ledView = LEDView(frame: NSRect(x: 0, y: 0, width: 24, height: thickness))
        super.init()
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            ledView.frame = button.bounds
            ledView.autoresizingMask = [.width, .height]
            button.image = nil
            button.title = ""
            button.addSubview(ledView)
        }
        statusItem.menu = makeMenu()
        startRenderLoop()
    }

    // MARK: - Render loop (PRD §1.2)

    /// Pulls the latest aggregated value at ~60Hz and maps it to LED brightness.
    /// `.common` run-loop mode keeps it ticking during menu tracking / window drags.
    private func startRenderLoop() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        renderTimer = timer
    }

    private func renderTick() {
        // Apply live LED preferences (color + glow); the cached NSColor avoids a
        // per-frame Color→NSColor conversion.
        let settings = AppSettings.shared
        if ledView.tintColor != settings.ledNSColor { ledView.tintColor = settings.ledNSColor }
        let glow = CGFloat(settings.glowIntensity)
        if ledView.glowIntensity != glow { ledView.glowIntensity = glow }

        // rolling60sP95 already carries the 10 MB/s floor, so it's always > 0.
        let ceiling = aggregator.rolling60sP95
        let ratio = ceiling > 0 ? aggregator.instantaneousRateBytesPerSec / ceiling : 0
        ledView.brightness = max(LEDView.minBrightness, min(1.0, CGFloat(ratio)))
    }

    // MARK: - Menu (PRD §1.4)

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(title: "Disk Activity", action: nil, keyEquivalent: "")
        menu.addItem(header)
        menu.addItem(readItem)
        menu.addItem(writeItem)
        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Blinken", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    /// Refresh the read/write rows when the menu opens, then keep them live at 1Hz
    /// while it stays open (PRD §1.4).
    func menuWillOpen(_ menu: NSMenu) {
        refreshRates()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshRates() }
        }
        RunLoop.main.add(timer, forMode: .common)
        menuRefreshTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = nil
    }

    private func refreshRates() {
        // Smoothed rate (steady, non-flickering) + cumulative total (odometer).
        readItem.title = "Read:   \(Self.formatRate(aggregator.smoothedReadRateBytesPerSec))   (\(Self.formatBytes(aggregator.totalBytesRead)))"
        writeItem.title = "Write:   \(Self.formatRate(aggregator.smoothedWriteRateBytesPerSec))   (\(Self.formatBytes(aggregator.totalBytesWritten)))"
    }

    private static func formatRate(_ bytesPerSec: Double) -> String {
        let mb = bytesPerSec / (1024 * 1024)
        if mb >= 1 { return String(format: "%.1f MB/s", mb) }
        return String(format: "%.0f KB/s", bytesPerSec / 1024)
    }

    /// Human-readable cumulative total (e.g. "661.3 GB"), matching the OS's figures.
    private static func formatBytes(_ bytes: UInt64) -> String {
        let capped = bytes > UInt64(Int64.max) ? Int64.max : Int64(bytes)
        return ByteCountFormatter.string(fromByteCount: capped, countStyle: .file)
    }

    // MARK: - Actions

    /// Opens (or re-focuses) the preferences window. We host `PreferencesView` in
    /// our own `NSWindow` rather than the SwiftUI `Settings` scene — for an
    /// LSUIElement app there's no app menu to reach Settings, and the AppKit
    /// `showSettingsWindow:` selector is deprecated on macOS 14+ ("use SettingsLink").
    @objc private func openPreferences() {
        if preferencesWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView()))
            window.title = "Blinken Preferences"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
