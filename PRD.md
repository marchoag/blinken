# Blinken — Product Requirements Document (v1.0)

**Codename:** Blinken
**Platform:** macOS 14.0+ (Sonoma and later)
**Architecture:** Universal 2 (Apple Silicon + Intel)
**Distribution:** Direct download (.dmg) from product website + Homebrew Cask
**Owner:** Marc Hoag / Axiomic, LLC
**Status:** Greenfield, v1.0 spec

---

## 0. Executive Summary

Blinken is a macOS menu bar utility that resurrects the ambient hardware-status indicators of pre-2010 personal computers — most centrally, the hard disk activity LED. The v1.0 release ships a single feature surface: a menu bar item that visually mimics an HDD activity LED (a single red light whose brightness reflects disk throughput in real time), plus a slim swap-usage bar. v1.0 also contains complete, non-user-facing scaffolding for a future "input odometer" module that will track lifetime keystrokes and trackpad activity.

**Product thesis:** Quiet utilities for people who miss when computers told you things. Blinken is the brand vehicle for a suite of ambient-information modules; the disk LED is module one.

**Non-goals for v1.0:**
- No per-process I/O attribution
- No floating HUD window (menu bar only)
- No themes or customization beyond brightness ceiling
- No exposed odometer UI (scaffolding only — counters run silently, ready for v1.1)
- No iCloud sync, no telemetry, no analytics, no account system

---

## 1. Visual & Interaction Design

### 1.1 Menu Bar Item — Resting State

A single composite menu bar item, approximately 32–40 pixels wide depending on swap bar visibility:

```
[LED] [swap bar]
```

- **LED:** A circular red indicator, ~14×14 logical pixels, rendered as a radial gradient (deep red core, slight black outer ring for "bezel" effect). Renders crisply on Retina displays.
- **Swap bar:** A vertical bar graph, ~4 pixels wide × 16 pixels tall, immediately to the right of the LED. Color = a muted amber/yellow. Height of filled portion = fraction of swap currently in use (0–100%).
- Spacing between LED and swap bar: ~2 pixels.
- The composite respects both light and dark menu bar modes; the LED's "off" state is a dim, almost-black red (not pure black — should look like an unlit but present LED).

### 1.2 LED Behavior — The Core Aesthetic

The LED's brightness is a continuous function of instantaneous disk throughput. **There is no discrete "blink"** — perceived blinking emerges naturally from bursty I/O patterns being mapped to a high-frequency brightness signal.

**Brightness mapping:**
- `brightness = clamp(currentThroughputBytesPerSec / rollingMaxThroughput, MIN_BRIGHTNESS, 1.0)`
- `MIN_BRIGHTNESS = 0.04` (faintly visible dim red — confirms the app is running)
- `rollingMaxThroughput` is a 60-second rolling 95th percentile, with a floor of 10 MB/s to prevent the LED from saturating on trivial I/O
- During sustained heavy I/O (e.g., a large file copy): LED glows steady-bright — correct, matches real HDD LED behavior during sequential transfers
- During light intermittent I/O (e.g., background indexing): LED pulses naturally — correct, matches real HDD LED behavior during seeks

**Rendering cadence:**
- LED redraws at 60Hz (display refresh rate, not the 120Hz sampling rate)
- Sampling layer collects at 120Hz; rendering layer pulls latest aggregated value at 60Hz
- This is intentional — flicker fusion makes >90Hz visual flashing imperceptible, so we sample fast and render at display rate

### 1.3 Swap Bar Behavior

- Updates at 1Hz (no need for higher cadence; swap usage doesn't change rapidly)
- Fill height = `usedSwapBytes / totalSwapBytes` (NOT `usedSwap / RAM` — total swap is the denominator)
- If total swap is 0 bytes (rare but possible on freshly-booted systems): bar shows as empty (no fill)
- Color: `#D4A017` (muted amber). Same color in light and dark mode.
- If `usedSwap / totalSwap > 0.85`: fill color shifts to `#E07020` (orange) — subtle warning that swap is nearly exhausted

### 1.4 Menu (on click)

Left-click or right-click on the menu bar item opens a standard `NSMenu`:

```
─────────────────────────────────
  Disk Activity
    Read:  ▓▓▓▓▓░░░  12.4 MB/s
    Write: ▓▓░░░░░░   3.1 MB/s
─────────────────────────────────
  Memory
    Swap used:  2.1 GB / 4.0 GB
    Pressure:   Normal
─────────────────────────────────
  Preferences…
  About Blinken
  Quit
─────────────────────────────────
```

- The read/write rates in the menu are the **only** place read vs. write is distinguished. The LED itself does not differentiate (single red LED, by user spec).
- Inline mini-bars use Unicode block characters (`▓░`) — no custom drawing required for the menu.
- Values update at 1Hz while menu is open.
- "Memory Pressure" reads from `memorystatus_get_level` (or equivalent via `host_statistics64`) and displays as: Normal / Warning / Critical.

### 1.5 Preferences Window

A simple, single-pane `Settings` scene (SwiftUI `Settings` scene introduced in macOS 13):

- **General**
  - [ ] Launch at login (uses `SMAppService.mainApp.register()`)
  - [ ] Show swap bar in menu bar (default: on)
  - LED brightness ceiling: slider 0.3 → 1.0 (default 1.0) — for users on OLED displays who find max brightness too aggressive
- **About**
  - Version, build, link to website, link to GitHub source, license info

No preference for color, no preference for blink pattern, no preference for sampling rate. Opinionated software ships faster.

---

## 2. Technical Architecture

### 2.1 Project Structure

```
Blinken/
├── Blinken.xcodeproj
├── Blinken/
│   ├── App/
│   │   ├── BlinkenApp.swift          // @main, SwiftUI App + Settings scene
│   │   ├── AppDelegate.swift               // Lifecycle, launch-at-login
│   │   └── Info.plist                      // LSUIElement = YES (no Dock icon)
│   ├── MenuBar/
│   │   ├── MenuBarController.swift         // NSStatusItem orchestration
│   │   ├── LEDView.swift                   // Custom NSView, draws the LED
│   │   ├── SwapBarView.swift               // Custom NSView, draws the swap bar
│   │   └── StatusMenu.swift                // NSMenu construction
│   ├── Modules/
│   │   ├── ModuleProtocol.swift            // Shared protocol for all modules
│   │   ├── DiskActivity/
│   │   │   ├── DiskActivityModule.swift    // Module entry point
│   │   │   ├── DiskStatsSampler.swift      // IOKit polling at 120Hz
│   │   │   ├── DiskStatsAggregator.swift   // Rolling stats, percentiles
│   │   │   └── SwapMonitor.swift           // sysctl vm.swapusage
│   │   └── InputOdometer/                  // v1.1 scaffolding — see §4
│   │       ├── InputOdometerModule.swift   // Stub module, increments counters silently
│   │       ├── EventTapManager.swift       // CGEventTap setup
│   │       ├── PermissionCoordinator.swift // Accessibility / Input Monitoring prompts
│   │       └── CounterStore.swift          // SQLite persistence
│   ├── Preferences/
│   │   └── PreferencesView.swift           // SwiftUI Settings scene
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   └── Blinken.entitlements
│   └── Support/
│       ├── Logger.swift                    // os.Logger wrapper
│       └── HighPriorityTimer.swift         // DispatchSourceTimer wrapper for 120Hz
└── BlinkenTests/
    └── DiskStatsAggregatorTests.swift
```

### 2.2 Core Frameworks & APIs

- **SwiftUI** for `Settings` scene and About window
- **AppKit** for menu bar (`NSStatusItem`, `NSStatusBar`) — `MenuBarExtra` is tempting but its custom rendering control is too limited for the LED effect; use traditional `NSStatusItem` with a custom `NSView`
- **IOKit** (`IOKit/storage/IOBlockStorageDriver.h`) — for raw disk statistics
- **DiskArbitration** — for enumerating mounted volumes and mapping BSD names to volumes (for the per-volume menu detail)
- **`sysctlbyname("vm.swapusage", ...)`** — for swap statistics
- **Mach host statistics** (`host_statistics64` with `HOST_VM_INFO64`) — for pageins/pageouts and memory pressure
- **CGEventTap** + **NSEvent global monitors** — for the input odometer scaffolding (v1.1)
- **GRDB.swift** (via Swift Package Manager) — SQLite wrapper for `CounterStore`. Pinned dependency.

### 2.3 Sampling Pipeline (Disk Activity)

```
[120Hz timer] → [DiskStatsSampler] → [DiskStatsAggregator] → [LEDView updates]
                       │                       │
                       ↓                       ↓
                [IOKit query]          [rolling 95th %ile,
                                        instantaneous rate,
                                        read/write split]
```

**`DiskStatsSampler`:**
- Uses `DispatchSourceTimer` on a dedicated background `DispatchQueue` (QoS: `.utility`) firing every 1/120 sec (~8.33ms)
- Each tick: enumerates all `IOBlockStorageDriver` entries via `IOServiceGetMatchingServices`, reads `Statistics` dict from each, sums `Bytes (Read)` and `Bytes (Write)` across all physical devices
- Emits `(timestamp, totalBytesRead, totalBytesWritten)` to the aggregator
- **Critical:** Apple Silicon Macs may expose virtual devices (APFS containers, snapshots) that double-count. Filter to physical devices only by checking `IOServiceClass == "IOMedia"` AND `Whole == true` AND `Removable == false || Removable == true` (include both, but dedupe by BSD name).

**`DiskStatsAggregator`:**
- Maintains a ring buffer of the last 7,200 samples (60 seconds × 120Hz)
- On each new sample, computes:
  - `instantaneousRateBytesPerSec` (delta over last sample, divided by sample interval)
  - `rolling60sP95` (used as the normalization ceiling for LED brightness)
  - Separate read and write rates (for the menu display)
- Publishes via Combine `@Published` properties for the views to observe
- Render loop reads at 60Hz (display refresh) — no need to push every 120Hz sample to the UI thread

**Why 120Hz sampling for a 60Hz render?**
- ProMotion displays are 120Hz; future-proofing without cost
- Higher-frequency sampling smooths out brief I/O spikes that would otherwise be missed
- IOKit calls are cheap (microseconds); no thermal or battery concern

### 2.4 Swap & Memory Monitoring

`SwapMonitor` runs on a 1Hz timer:

```swift
var swapUsage = xsw_usage()
var size = MemoryLayout<xsw_usage>.size
sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0)
// swapUsage.xsu_total, swapUsage.xsu_used, swapUsage.xsu_avail
```

Memory pressure via `host_statistics64`:

```swift
var stats = vm_statistics64()
var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
host_statistics64(mach_host_self(), HOST_VM_INFO64, ..., &count)
// stats.compressions, stats.swapins, stats.swapouts → pressure signal
```

Pressure mapping: Apple's `memorystatus_get_level` SPI is private; use the public proxy `os_proc_available_memory()` combined with `swapouts > 0` as a heuristic. Display as Normal / Warning / Critical per Apple's documented thresholds.

### 2.5 Module Protocol (For Suite Extensibility)

```swift
protocol BlinkenModule: AnyObject {
    static var identifier: String { get }
    static var displayName: String { get }

    var isEnabled: Bool { get set }
    var requiredPermissions: [SystemPermission] { get }

    func start() async throws
    func stop()

    /// Optional UI contribution to the menu bar composite view
    var menuBarView: NSView? { get }

    /// Optional contribution to the dropdown NSMenu
    func menuItems() -> [NSMenuItem]
}

enum SystemPermission {
    case accessibility
    case inputMonitoring
    case fullDiskAccess  // not needed for v1, but enumerated
}
```

`DiskActivityModule` and `InputOdometerModule` both conform. This is the seam along which v1.1, v1.2, etc. modules will slot in.

---

## 3. Permissions, Entitlements, and Signing

### 3.1 Required Permissions (v1.0)

**Disk Activity Module:** None. IOKit storage statistics are readable without elevated permissions on macOS 14+.

**Input Odometer Module (scaffolding):** Accessibility and/or Input Monitoring. The scaffolding will request these on first launch ONLY IF the module is enabled (default in v1.0: disabled). If disabled, no permission prompt fires.

### 3.2 Entitlements

`Blinken.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.cs.allow-jit</key>
    <false/>
</dict>
</plist>
```

**Sandbox: OFF.** This is a deliberate choice. The Mac App Store would require sandboxing, which would restrict IOKit access and force a feature-cut version. The product is distributed direct + Homebrew, so the sandbox provides no value and would hurt the disk module.

### 3.3 Code Signing & Notarization

- Signed with Marc's Apple Developer ID Application certificate (already paid the $100 tax)
- Hardened Runtime: ON
- Notarized via `xcrun notarytool submit ... --wait`
- Stapled with `xcrun stapler staple Blinken.app`

### 3.4 Distribution Artifacts

Two artifacts produced by the build/release script:

1. **`Blinken-1.0.0.dmg`** — drag-to-Applications installer, signed + notarized + stapled. Hosted on the product website.
2. **Homebrew Cask formula** — submitted as a PR to `homebrew-cask`, pointing at the DMG URL with the SHA256 checksum.

Build/release script: `scripts/release.sh` (the PRD does not specify CI; Marc can run this locally on his Mac mini M4 Pro until volume justifies GitHub Actions).

---

## 4. Input Odometer Scaffolding (v1.1 Prep)

v1.0 ships the InputOdometer module wired up, running, persisting data — but with no menu surface and no preferences exposure. Activating it in v1.1 should be a flag flip plus UI work, no architectural changes.

### 4.1 v1.0 Behavior

- Module is registered with the `ModuleRegistry` but `isEnabled = false` by default
- A hidden launch-arg `--enable-odometer-dev` flips it on for Marc's testing
- When enabled:
  - Triggers permission flow on first activation (request Accessibility + Input Monitoring via `AXIsProcessTrustedWithOptions` and `IOHIDCheckAccess`)
  - Installs a `CGEventTap` on the session at `kCGSessionEventTap` listening for `kCGEventKeyDown`, `kCGEventLeftMouseDown`, `kCGEventRightMouseDown`, `kCGEventOtherMouseDown`, `kCGEventScrollWheel`, `kCGEventMouseMoved`
  - On each event:
    - Keystrokes → `counterStore.increment(.keystrokes, by: 1, app: frontmostBundleID)`
    - Clicks → `counterStore.increment(.clicks, by: 1, app: frontmostBundleID)`
    - Mouse moves → batch Euclidean distance accumulation, flush to store every 500ms as `counterStore.increment(.cursorPixels, by: batchedPixels, app: frontmostBundleID)`
- All counter increments are append-only to an SQLite DB at `~/Library/Application Support/Blinken/odometer.sqlite`

### 4.2 SQLite Schema

```sql
CREATE TABLE counter_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp REAL NOT NULL,                  -- Unix epoch
    counter_type TEXT NOT NULL,               -- 'keystrokes' | 'clicks' | 'cursor_pixels'
    delta INTEGER NOT NULL,
    bundle_id TEXT                            -- nullable
);
CREATE INDEX idx_counter_events_timestamp ON counter_events(timestamp);
CREATE INDEX idx_counter_events_type_time ON counter_events(counter_type, timestamp);

CREATE TABLE counter_totals (                 -- denormalized rolling totals for O(1) reads
    counter_type TEXT PRIMARY KEY,
    total INTEGER NOT NULL DEFAULT 0,
    updated_at REAL NOT NULL
);
```

Writes are batched (1Hz flush of an in-memory buffer) to avoid SQLite write amplification under high event rates.

### 4.3 v1.0 Acceptance for the Stub

- App launches with module disabled by default → no permission prompts, no event tap, no SQLite file created
- App launched with `--enable-odometer-dev` → permission prompts appear, taps install, SQLite file is created and populated, counters increment correctly
- Killing the app → counters persist; relaunching resumes accumulation
- Verified via a test script `scripts/dump_odometer.swift` that prints current totals

No menu UI, no preference toggle, no About-screen mention. This is purely architectural prep.

---

## 5. Performance Requirements

- **CPU:** < 0.5% average on M-series, < 1.5% on Intel, at idle (no I/O happening). Measured via Activity Monitor over 60 seconds.
- **Memory:** < 30 MB resident
- **Energy Impact:** "Low" rating in Activity Monitor under sustained operation
- **No frame drops** in the menu bar LED rendering — must hit 60Hz cleanly even when system is under load
- **Sampling jitter:** 120Hz disk sampling can tolerate up to ±2ms jitter; beyond that, drop the sample rather than catch up (no burst-sampling)

---

## 6. Testing Strategy

### 6.1 Unit Tests

- `DiskStatsAggregator`: deterministic tests with synthetic sample streams covering quiet, bursty, sustained, and pathological (e.g., counter rollover) inputs
- `CounterStore`: SQLite read/write correctness, batch flush behavior, total reconciliation

### 6.2 Manual QA Checklist (v1.0 Release Gate)

- [ ] Fresh install on clean macOS 14 — launches, LED dim-glows
- [ ] Fresh install on macOS 15 — same
- [ ] Run `dd if=/dev/zero of=/tmp/test.bin bs=1m count=1024` — LED glows steady-bright, swap bar reflects pressure
- [ ] Wait 5 minutes idle — LED returns to dim-glow, no growth in memory footprint
- [ ] Toggle "Launch at login" — verify in System Settings > General > Login Items
- [ ] Quit and relaunch — no crash, no leftover processes
- [ ] Activity Monitor — confirms CPU and Energy targets
- [ ] Notarization staple — `spctl -a -vvv Blinken.app` returns "accepted"
- [ ] Install via Homebrew Cask in a fresh user account — works
- [ ] Launch with `--enable-odometer-dev` — permission flows fire, SQLite file created, counters increment

### 6.3 Tests Explicitly Out of Scope for v1.0

- Multi-display behavior (should Just Work; not extensively QA'd)
- Localization (English only in v1.0)
- Accessibility (VoiceOver) — menu bar utility, not blocking; flagged for v1.2

---

## 7. Release Plan

**v1.0 (this PRD):** Disk LED + swap bar + odometer scaffolding. Ship to website + Homebrew Cask.

**v1.0.x:** Bug fixes only.

**v1.1:** Input odometer goes live — preferences toggle, menu UI, lifetime counters visible. Permission flow polished. Per-app breakdown view.

**v1.2:** Third module — likely network throughput needle (the old modem-light aesthetic), or temperature/fan tach. Decided by user demand post-v1.1.

---

## 8. Open Questions for Implementation

These are items the implementer (Claude Code or human) should flag back to Marc, not silently decide:

1. **Exact LED gradient values** — the PRD specifies "radial gradient, deep red core, slight black outer ring." The specific RGBA values should be sketched in an `LEDView` preview and approved visually before final commit.
2. **App icon** — needed for the .dmg, Finder, About box. Not specified. Suggest commissioning or generating a simple "red LED on a dark background" icon; out of scope for this PRD.
3. **Website copy** — `blinken.app` or similar domain. Out of scope.
4. **Homebrew Cask formula** — Marc to submit PR after first signed/notarized build is hosted.

---

## 9. Glossary

- **DXA, EMU:** Not relevant here (these are Office Open XML units). Ignore if Claude Code surfaces them.
- **IOKit storage statistics:** Apple's public API for reading per-device read/write byte counts.
- **`vm.swapusage`:** A `sysctl` MIB returning total/used/free swap in bytes.
- **`CGEventTap`:** Quartz Event Services API for system-wide event observation. Requires Accessibility permission.
- **`LSUIElement`:** Info.plist key that hides an app from the Dock and ⌘-Tab switcher.
- **Notarization:** Apple's automated malware scan + stapling process required for direct-distribution macOS apps to launch without Gatekeeper warnings.

---

*End of PRD v1.0.*
