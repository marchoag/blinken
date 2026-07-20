# Changelog

All notable changes to Blinken. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] – 2026-07-19

### Changed

- **The disk odometer is now yours to anchor.** Read and Write each show a single total, measured from a point you control. A new row reports the span those totals cover (“Measuring for 3h 42m”); clicking it rebases both to zero and restarts the clock — useful when you want to watch what a specific copy, build, or backup actually costs.

### Removed

- **The since-boot figure in parentheses** on the Read and Write rows. For anyone launching Blinken at login it sat within a fraction of a percent of the session total, and a number that only grows and can't be reset isn't one you can act on. The since-boot counters are still what macOS reports in Activity Monitor if you want them.

## [1.0.1] – 2026-05-29

### Fixed

- Privacy Policy and Terms in the Preferences About section are now clickable links.

## [1.0.0] – 2026-05-28

Initial release.

### Added

- **Menu bar HDD-activity LED.** A circular red LED that brightens with real disk read/write throughput. Adaptive sampling rate (30 Hz active, 5 Hz idle) keeps Activity Monitor's Energy Impact reading "Low" on a quiet Mac.
- **Slim amber swap-usage bar** next to the LED. Fill height tracks swap depth relative to system RAM; lerps toward an orange warning hue above 85% of RAM in swap. A soft glow intensifies as the bar fills.
- **Memory section in the dropdown.** Read/write totals (since this app launched + since last reboot), RAM in use, swap on disk, and the kernel's memory-pressure level. Numbers match Activity Monitor.
- **Preferences pane.** LED color and glow intensity, swap-bar color, Launch at Login, Reset Appearance to Defaults. The Preferences About header doubles as a live preview of your color and glow choices.
- **Signed + notarized DMG** distribution for **macOS 15** (Sequoia) on **Apple Silicon and Intel** (Universal 2).

### Privacy

Local-only. Reads `IOKit` disk counters and standard macOS memory APIs. No accounts, no telemetry, no network requests, no data leaves your machine.

[1.0.2]: https://github.com/marchoag/blinken/releases/tag/v1.0.2
[1.0.1]: https://github.com/marchoag/blinken/releases/tag/v1.0.1
[1.0.0]: https://github.com/marchoag/blinken/releases/tag/v1.0.0
