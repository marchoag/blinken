//
//  MenuBarController.swift
//  Blinken
//
//  Orchestrates the NSStatusItem: hosts the composite LED + swap bar view
//  and attaches the dropdown StatusMenu (PRD §1.1, §2.2).
//

import AppKit
import SwiftUI

/// Owns the menu bar status item: hosts the `LEDView` and `SwapBarView`, drives
/// them from `DiskStatsAggregator` and `SwapMonitor` on a ~60Hz render loop, and
/// presents the dropdown (Disk Activity + Memory + Preferences + Quit).
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private let aggregator: DiskStatsAggregator
    private let swap: SwapMonitor
    private let statusItem: NSStatusItem
    private let ledView: LEDView
    private let swapBarView: SwapBarView

    private var renderTimer: Timer?
    private var menuRefreshTimer: Timer?
    private var preferencesWindow: NSWindow?

    private let readItem = NSMenuItem(title: "Read:  —", action: nil, keyEquivalent: "")
    private let writeItem = NSMenuItem(title: "Write:  —", action: nil, keyEquivalent: "")
    private let swapItem = NSMenuItem(title: "Swap used:  —", action: nil, keyEquivalent: "")
    private let pressureItem = NSMenuItem(title: "Pressure:  —", action: nil, keyEquivalent: "")

    init(aggregator: DiskStatsAggregator, swap: SwapMonitor) {
        self.aggregator = aggregator
        self.swap = swap
        // Composite item: LED slot (≈22pt) + small gap + swap-bar slot (≈12pt).
        self.statusItem = NSStatusBar.system.statusItem(withLength: 36)
        let thickness = NSStatusBar.system.thickness
        self.ledView = LEDView(frame: NSRect(x: 0, y: 0, width: 22, height: thickness))
        self.swapBarView = SwapBarView(frame: NSRect(x: 24, y: 0, width: 12, height: thickness))
        super.init()
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            // Explicit frames partition the button into LED + swap slots; status item
            // length is fixed, so no autoresizing needed.
            button.image = nil
            button.title = ""
            button.addSubview(ledView)
            button.addSubview(swapBarView)
        }
        statusItem.menu = makeMenu()
        startRenderLoop()
    }

    // MARK: - Render loop (PRD §1.2)

    /// Pulls the latest aggregated values at ~60Hz and updates both views.
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

        // While Preferences is open, peg the LED at full brightness so the user can
        // preview the chosen color + glow live — otherwise it just sits dim at idle
        // I/O and the controls look like they do nothing.
        if preferencesWindow?.isVisible == true {
            ledView.brightness = 1.0
        } else {
            // rolling60sP95 already carries the 10 MB/s floor, so it's always > 0.
            let ceiling = aggregator.rolling60sP95
            let ratio = ceiling > 0 ? aggregator.instantaneousRateBytesPerSec / ceiling : 0
            ledView.brightness = max(LEDView.minBrightness, min(1.0, CGFloat(ratio)))
        }

        // Swap bar: fill fraction + live tint from settings.
        let total = swap.swapTotalBytes
        let fraction: CGFloat = total > 0 ? CGFloat(swap.swapUsedBytes) / CGFloat(total) : 0
        if swapBarView.usedFraction != fraction { swapBarView.usedFraction = fraction }
        if swapBarView.tintColor != settings.swapNSColor { swapBarView.tintColor = settings.swapNSColor }
    }

    // MARK: - Menu (PRD §1.4)

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let diskHeader = NSMenuItem(title: "Disk Activity", action: nil, keyEquivalent: "")
        menu.addItem(diskHeader)
        menu.addItem(readItem)
        menu.addItem(writeItem)
        menu.addItem(.separator())

        let memoryHeader = NSMenuItem(title: "Memory", action: nil, keyEquivalent: "")
        menu.addItem(memoryHeader)
        menu.addItem(swapItem)
        menu.addItem(pressureItem)
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

    /// Refresh menu rows when it opens, then keep them live at 1Hz while open
    /// (PRD §1.4).
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
        // Disk amounts only — the menu is the odometer; the LED conveys live rate.
        //   primary = bytes since app launch (this session)
        //   parens  = bytes since last reboot (raw IOKit counter)
        readItem.title  = "Read:   \(Self.formatBytes(aggregator.sessionBytesRead))   (\(Self.formatBytes(aggregator.totalBytesRead)))"
        writeItem.title = "Write:   \(Self.formatBytes(aggregator.sessionBytesWritten))   (\(Self.formatBytes(aggregator.totalBytesWritten)))"

        // Memory: swap used / currently-allocated swap + kernel pressure level.
        swapItem.title = "Swap used:   \(Self.formatBytes(swap.swapUsedBytes)) / \(Self.formatBytes(swap.swapTotalBytes))"
        pressureItem.title = "Pressure:   \(swap.pressure.label)"
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
            let hosting = NSHostingController(rootView: PreferencesView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Blinken Preferences"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            preferencesWindow = window
        }
        guard let window = preferencesWindow else { return }
        anchorBelowStatusItem(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Hangs the window from the status item: top edge just under the menu bar,
    /// horizontally centered on the item but clamped to stay on screen. Uses the
    /// top-left anchor so dynamic content height grows downward.
    private func anchorBelowStatusItem(_ window: NSWindow) {
        guard let itemWindow = statusItem.button?.window else { window.center(); return }
        let item = itemWindow.frame
        let visible = (itemWindow.screen ?? NSScreen.main)?.visibleFrame ?? item
        let width = window.frame.width
        var x = item.midX - width / 2
        x = min(x, visible.maxX - width - 8)
        x = max(x, visible.minX + 8)
        window.setFrameTopLeftPoint(NSPoint(x: x, y: item.minY - 2))
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
