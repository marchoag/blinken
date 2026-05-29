# Changelog

All notable changes to Blinken. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.0.0]: https://github.com/marchoag/blinken/releases/tag/v1.0.0
