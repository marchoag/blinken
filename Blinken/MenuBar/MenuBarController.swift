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
    private let sessionItem = NSMenuItem(title: "Measuring for —", action: nil, keyEquivalent: "")
    private let ramItem = NSMenuItem(title: "RAM used:  —", action: nil, keyEquivalent: "")
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

    /// Pulls the latest aggregated values at ~30Hz and updates both views.
    /// `.common` run-loop mode keeps it ticking during menu tracking / window
    /// drags. (Originally 60Hz; halving it cut a lot of idle main-thread
    /// wakeups, which is what Activity Monitor's "Energy Impact" actually
    /// measures. 30Hz on a 14pt LED is still indistinguishable to the eye.)
    private func startRenderLoop() {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
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

        // Swap bar: fraction = swap used / total system RAM. Stable denominator;
        // the kernel-allocated pool grows on demand on macOS, so used/RAM is what
        // actually signals memory pressure. Live tint from settings.
        let ram = swap.systemRAMBytes
        let raw = ram > 0 ? CGFloat(swap.swapUsedBytes) / CGFloat(ram) : 0
        let fraction = max(0, min(1, raw))
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
        sessionItem.action = #selector(resetCounters)
        sessionItem.target = self
        menu.addItem(sessionItem)
        menu.addItem(.separator())

        let memoryHeader = NSMenuItem(title: "Memory", action: nil, keyEquivalent: "")
        menu.addItem(memoryHeader)
        menu.addItem(ramItem)
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
        // One number per row, measured from a user-controllable anchor. (Through
        // 1.0.1 each row also carried a since-boot figure in parentheses; for anyone
        // launching Blinken at login the two were near-identical, and an
        // ever-growing since-boot total isn't something you can act on.)
        readItem.title  = "Read:   \(Self.formatBytes(aggregator.sessionBytesRead))"
        writeItem.title = "Write:   \(Self.formatBytes(aggregator.sessionBytesWritten))"
        // The span is what makes the totals interpretable — "1.55 TB" says nothing
        // without it — and clicking the row rebases both to now.
        sessionItem.title = "Measuring for \(Self.formatElapsed(aggregator.sessionElapsedSeconds))   ·   Reset"

        // Memory: RAM used (% of total) + Swap used (absolute) + pressure level.
        // The earlier "% of RAM" parenthetical on the swap line read ambiguously
        // — like *RAM* was that fraction used — so each metric now stands alone.
        let ram = swap.systemRAMBytes
        let ramUsed = swap.ramUsedBytes
        let ramPct = ram > 0 ? Int((Double(ramUsed) / Double(ram) * 100).rounded()) : 0
        ramItem.title = "RAM used:    \(Self.formatBytesMemory(ramUsed)) / \(Self.formatBytesMemory(ram))   (\(ramPct)%)"
        swapItem.title = "Swap used:   \(Self.formatBytesMemory(swap.swapUsedBytes))"
        pressureItem.title = "Pressure:    \(swap.pressure.label)"
    }

    /// Human-readable disk total (e.g. "661.3 GB"); decimal GB to match Activity
    /// Monitor / drive manufacturers' conventions.
    private static func formatBytes(_ bytes: UInt64) -> String {
        let capped = bytes > UInt64(Int64.max) ? Int64.max : Int64(bytes)
        return ByteCountFormatter.string(fromByteCount: capped, countStyle: .file)
    }

    /// Memory-style formatting (1 GB = 2³⁰ B) — matches Apple's marketing numbers
    /// for RAM and swap, i.e. what users expect when reading "24 GB."
    private static func formatBytesMemory(_ bytes: UInt64) -> String {
        let capped = bytes > UInt64(Int64.max) ? Int64.max : Int64(bytes)
        return ByteCountFormatter.string(fromByteCount: capped, countStyle: .memory)
    }

    /// Compact span for the session odometer: "47s", "12m", "3h 42m", "2d 5h".
    /// Deliberately coarse — this is context for the byte totals, not a stopwatch,
    /// so the largest two units are enough at every scale.
    static func formatElapsed(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let (days, hours) = (total / 86_400, (total % 86_400) / 3_600)
        let (minutes, secs) = ((total % 3_600) / 60, total % 60)
        switch total {
        case ..<60:     return "\(secs)s"
        case ..<3_600:  return "\(minutes)m"
        case ..<86_400: return "\(hours)h \(minutes)m"
        default:        return "\(days)d \(hours)h"
        }
    }

    // MARK: - Actions

    /// Rebases the disk odometer to now. The menu is open when this fires, so the
    /// 1Hz refresh timer repaints the zeroed rows on its next tick; refreshing here
    /// too makes it feel instant rather than up-to-a-second late.
    @objc private func resetCounters() {
        aggregator.resetSessionCounters()
        refreshRates()
    }

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
            // Force the content size so centering math has a stable frame.
            // Must match PreferencesView's `.frame(...)` — kept in sync manually.
            window.setContentSize(NSSize(width: 560, height: 600))
            preferencesWindow = window
            // NSWindow.center() only centers horizontally and pins y near the top of
            // the screen — on a notched display that lands the window against the
            // notch. Center within the screen's *visible* frame (below menu bar /
            // above dock) instead.
            centerOnVisibleFrame(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    private func centerOnVisibleFrame(_ window: NSWindow) {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { window.center(); return }
        let w = window.frame.width
        let h = window.frame.height
        let origin = NSPoint(
            x: visible.minX + (visible.width - w) / 2,
            y: visible.minY + (visible.height - h) / 2
        )
        window.setFrameOrigin(origin)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
