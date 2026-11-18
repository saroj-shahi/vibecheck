# Pulse

A lightweight macOS menu bar system monitor (macOS 14+), written in Swift with SwiftUI + AppKit.

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

Settings (gear icon in any panel, or open the app again): choose menu bar items, update interval, launch at login.

## Build & run

```bash
./build.sh            # builds build/Pulse.app
open build/Pulse.app
./build.sh --install  # also copies it to /Applications
```

Debug: `swift build && .build/debug/Pulse --dump` prints one sample from every monitor.

## Layout

- `Sources/Pulse/Monitors/` — data collectors (Mach host stats, sysctl, IOKit, IOPowerSources, SMC, HID temperature sensors, `ps`)
- `Sources/Pulse/App/` — `SystemStats` (timer + histories), settings, status items
- `Sources/Pulse/Views/` — menu bar labels, panels, charts, settings window

## Ideas for next steps

- Per-process network usage, public IP, Wi-Fi details
- Combined single-item mode, notifications/alerts, weather & clock modules
