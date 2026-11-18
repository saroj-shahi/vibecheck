# VibeCheck

A lightweight macOS menu bar system monitor that tells you if your Mac is vibing or cooked (macOS 14+), written in Swift with SwiftUI + AppKit.

A **vibe ring** sums it all up: full and monochrome while your Mac is vibing, two-thirds and yellow when
it's mid, one-third and red when it's cooked (sustained CPU, memory pressure, heat, low disk or battery,
thermal throttling). The deck header turns that into a sentence, e.g. "Kinda mid: CPU has been busy at 72%.
Xcode is the loudest at 140% CPU." States only change after two consecutive samples, so nothing flickers.

Each module gets its own menu bar item (or one combined item, the default for new installs). Clicking opens the **deck**: a glass panel
under the menu bar with a live tile per stat. Click a tile (or use the arrow keys and Return) and it unfolds
into that module's detail view; Esc folds back, then closes. `⌘1`–`⌘9` jump between modules inside the deck,
`⌘,` opens Settings. Separate items open the deck straight on their module.

| Module  | Menu bar                     | Panel |
|---------|------------------------------|-------|
| CPU     | mini history bars + %        | user/system/idle, history graph, per-core bars, P/E cores, load average, thermal state, top apps or processes |
| GPU     | mini history bars + %        | utilization graph, renderer / tiler split, GPU memory in use, model and core count (each GPU on Intel Macs) |
| Memory  | pressure-colored gauge + %   | composition bar (app/wired/compressed/cached), history, pressure, swap, top apps (helpers grouped, with icons) or processes |
| Network | ↑/↓ rates; arrows light up while data moves, "Offline" when disconnected | mirrored up/down graph, status, interface, local IP, totals since boot, per-interface traffic (Wi-Fi, Ethernet, VPN…), top apps by traffic |
| Disk    | read/write rates             | I/O graph, every local volume with capacity bars |
| Sensors | hottest temperature         | SoC/CPU, SSD and battery temperatures with history, fan speed and range, system and adapter power, full list of every sensor |
| Battery | icon + % (off by default)    | state, time remaining, power draw, health, cycle count, Bluetooth device batteries (AirPods, Apple keyboards/mice/trackpads) |
| Weather | condition icon + temperature (off by default) | current conditions, next 12 hours, 7-day forecast with ranges ([Open-Meteo](https://open-meteo.com/), no key, city search instead of location access) |
| Clock   | time (off by default)        | big time and date, month calendar (opens Calendar), world clocks with day/night and offset |

Detail views lead with one big number and a short summary, then the chart, then **who's responsible**
(top apps), with everything else behind a remembered **Details** toggle. Hover any chart to scrub it: a
hairline and value bubble follow the pointer (with a trackpad tick at the peak). Every chart has a sliding
**Live / 1H / 24H** pill, and switching ranges morphs the line instead of redrawing it. Hour and day history are averaged (6 s and 144 s buckets),
saved to `~/Library/Application Support/VibeCheck/history.json`, and survive restarts; sleep shows as gaps.

Settings (gear icon in any panel, or open the app again):

- **General:** separate items or **one combined item** (icon tabs switch modules), which items to show and how each one looks (graph + value, icon + value, value only), colorful or single-color graphs, spacing (normal / compact / tight), update interval, launch at login.
- **Clock:** menu bar format (locale-aware), seconds, world clocks with city search.
- **Weather:** city search, °C / °F.
- **Backup:** export / import settings as a .plist, or reset to defaults.
- **Menu Bar:** a live preview drawn with the real labels, style, spacing, vibe ring, and drag-to-reorder items. **Fit around the camera notch** (on by default): on a notched display the combined item shows as many stats as fit beside the notch, in your order, plus a "+N" badge; everything stays in the deck.
- **Alerts:** rules read as sentences ("Tell me when **CPU usage** is **above** **90%** for **1 min**"); click a word to change it, drag the number sideways to adjust it, preview the banner. Notifications such as "CPU above 90% for 1 min", "temperature above 95 °C", "battery below 15%", "startup disk below 10% free". Each fires once, then re-arms after the value recovers (5 min cooldown).
- **Shortcuts:** `⌃⌥⌘1`…`⌃⌥⌘9` open CPU, GPU, Memory, Network, Disk, Sensors, Battery, Clock, Weather from any app (modifier keys configurable).

## Build & run

```bash
./build.sh            # builds build/VibeCheck.app
open build/VibeCheck.app
./build.sh --install  # also copies it to /Applications
/Applications/VibeCheck.app/Contents/MacOS/VibeCheck --login-item on   # or off / status
```

Debug: `swift build && .build/debug/VibeCheck --dump` prints one sample from every monitor.
`build/VibeCheck.app/Contents/MacOS/VibeCheck --deck-demo` opens the deck, unfolds CPU, folds back and logs the window frame at each step.

Tests: `swift test` (alert timing/cooldown, history bucketing/persistence, app grouping, world clocks, menu bar layout, per-app network parsing, weather decoding, settings backup).

## Layout

- `Sources/VibeCheck/Monitors/` — data collectors (Mach host stats, sysctl, IOKit, IOPowerSources, SMC, HID temperature sensors, `ps`)
- `Sources/VibeCheck/App/` — `SystemStats` (timer + histories), settings, status items
- `Sources/VibeCheck/Views/` — menu bar labels, panels, charts, settings window

## Ideas for next steps

- Per-process network usage, public IP, Wi-Fi details
- Fan control (needs a privileged helper), notification history, iCloud settings sync
