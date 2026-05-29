# Blinken

A small red lamp in your menu bar, brightening when your disk is working.
The ambient HDD-activity LED of pre-2010 personal computers, restored as software.

→ **[labs.axiomic.ai/blinken](https://labs.axiomic.ai/blinken)**

## What it does

- **Live disk activity.** A circular red LED in the menu bar that brightens with disk read/write throughput. Adaptive sampling: 30 Hz when there's I/O, 5 Hz when your Mac is at rest.
- **Memory pressure.** A slim amber bar next to the LED fills with swap depth relative to your RAM. Warms toward orange when your Mac is leaning on the swap file.
- **At-a-glance numbers.** Click the LED for read/write totals (this session and since last reboot), RAM in use, swap on disk, and the kernel's pressure level. Same metrics Activity Monitor shows, one click away from anywhere.

## Install

Download the signed DMG from the [latest release](https://github.com/marchoag/blinken/releases/latest/download/Blinken.dmg). Drag `Blinken.app` to `/Applications`. Launch.

Requires **macOS 15 (Sequoia) or later**, on Apple Silicon or Intel.

## Customize

Click the LED → **Preferences**. Pick the LED color, the swap-bar color, your glow intensity, and toggle Launch at Login. Reset to defaults at any time.

## Privacy

Blinken is local-only. It reads system disk counters via `IOKit` and memory stats via standard macOS APIs. No accounts, no telemetry, no servers, no data ever leaves your machine.

Full policy: [labs.axiomic.ai/blinken/privacy](https://labs.axiomic.ai/blinken/privacy.html).

## Build from source

```bash
brew install xcodegen
git clone https://github.com/marchoag/blinken.git
cd blinken
xcodegen generate
open Blinken.xcodeproj
```

⌘B to build, ⌘R to run. Requires Xcode 26+ and macOS 15+.

To cut a signed, notarized DMG yourself, see [`scripts/release.sh`](./scripts/release.sh) (one-time setup documented in the script header).

## License

[MIT](./LICENSE). Use it however you like; just keep the copyright notice.

## Credits

Made with ❤️ in Marin County, California by [Marc Hoag](https://marchoag.com).
© 2026 [Axiomic, LLC](https://axiomic.ai).
