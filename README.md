# VibeCheck

A lightweight macOS menu bar system monitor that tells you if your Mac is vibing or cooked (macOS 14+), written in Swift with SwiftUI + AppKit.

Each module gets its own menu bar item; click one for a detailed panel.

| Module  | Menu bar                     | Panel |
|---------|------------------------------|-------|
| CPU     | mini history bars + %        | user/system/idle, history graph, per-core bars, P/E cores, load average, thermal state, top processes |
| GPU     | mini history bars + %        | utilization graph, renderer / tiler split, GPU memory in use, model and core count (each GPU on Intel Macs) |
| Memory  | pressure-colored gauge + %   | composition bar (app/wired/compressed/cached), history, pressure, swap, top processes |
| Network | ↑/↓ rates                    | mirrored up/down graph, interface, local IP, totals since boot |
| Disk    | read/write rates             | I/O graph, every local volume with capacity bars |
| Sensors | hottest temperature         | SoC/CPU, SSD and battery temperatures with history, fan speed and range, system and adapter power, full list of every sensor |
| Battery | icon + % (off by default)    | state, time remaining, power draw, health, cycle count |

Every chart has a **Live / 1H / 24H** switch. Hour and day history are averaged (6 s and 144 s buckets),
saved to `~/Library/Application Support/VibeCheck/history.json`, and survive restarts; sleep shows as gaps.

Settings (gear icon in any panel, or open the app again):

- **General:** separate items or **one combined item** (icon tabs switch modules), which items to show, update interval, launch at login.
- **Alerts:** notifications such as "CPU above 90% for 1 min", "temperature above 95 °C", "battery below 15%", "startup disk below 10% free". Each fires once, then re-arms after the value recovers (5 min cooldown).
- **Shortcuts:** `⌃⌥⌘1`…`⌃⌥⌘7` open CPU, GPU, Memory, Network, Disk, Sensors, Battery from any app (modifier keys configurable).

## Build & run

```bash
./build.sh            # builds build/VibeCheck.app
open build/VibeCheck.app
./build.sh --install  # also copies it to /Applications
```

Debug: `swift build && .build/debug/VibeCheck --dump` prints one sample from every monitor.

Tests: `swift test` (alert timing/cooldown and history bucketing/persistence).

## Layout

- `Sources/VibeCheck/Monitors/` — data collectors (Mach host stats, sysctl, IOKit, IOPowerSources, SMC, HID temperature sensors, `ps`)
- `Sources/VibeCheck/App/` — `SystemStats` (timer + histories), settings, status items
- `Sources/VibeCheck/Views/` — menu bar labels, panels, charts, settings window

## Ideas for next steps

- Per-process network usage, public IP, Wi-Fi details
- Bluetooth device batteries, per-app memory grouping, menu bar display options
- Clock & world clocks, weather, per-interface and per-app network usage
