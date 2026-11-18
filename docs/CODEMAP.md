# VibeCheck code map

Where things live, so a task can open the right file first. One line per file; keep it current when files
are added or split. Decisions and history are in [IMPROVEMENT_PLAN.md](IMPROVEMENT_PLAN.md).

## App/ (state, logic, system access)

| File | What's in it |
|---|---|
| `AppDelegate.swift` | `StatusItemController` (one menu bar item: kinds `.single(Module)`, `.combined`, `.vibe`, `.keepAwake`), `AppDelegate` (launch, `syncItems` / reorder rebuild by `statusItemGeneration`, deck/Settings opening, shortcuts, `--deck-demo`) |
| `AppSettings.swift` | `Module` enum (10 modules, order, symbols, label styles), `LabelStyle`, `Palette`, `AppSettings` (every setting, defaults domain `local.vibecheck.app`), `autosaveName` |
| `ItemOptions.swift` | Per-item menu bar options (Agents: which agents, % left/used/tokens, windows, reset; Memory, Network, Disk, Battery, Sensors) + `AgentUsageSample.menuBarContent` |
| `SystemStats.swift` | The tick: samples every monitor, histories, demand counters (`processDemand`, `networkAppDemand`, `sensorDemand`), vibe input, listening ports |
| `Vibe.swift` | Vibe score (vibing / mid / cooked) and the verdict sentence |
| `Alerts.swift` | `AlertMetric`, `AlertRule` (sentence alerts), `AlertEngine` (evaluate, notify, history log) |
| `KeepAwake.swift` | Sessions (`AwakeEnd`, focus sessions, triggers: power / display), IOKit assertion |
| `KeepAwakeMenu.swift` | Native right-click menu of the Keep Awake menu bar item |
| `Deck.swift` | `DeckPanel` (borderless non-activating NSPanel), `DeckController` (open/close, frame, keys, outside clicks) |
| `AgentUsage.swift` | `AgentUsageStore` (rescans agent logs every 60 s, merges live Claude limits) |
| `ClaudeLimits.swift` | Live Claude limits from the user's `claude` CLI (`get_usage` control request); opt-in |
| `ProcessKiller.swift` | Quit / Force Quit with protected processes and pid start-time identity |
| `QuickActions.swift` | Quick toggles: dark mode (System Events), mic mute (CoreAudio), empty Trash (Finder) |
| `SecureInput.swift` | Which app holds Secure Event Input (shortcuts paused) |
| `BluetoothSnooze.swift` | Bluetooth off while asleep (private IOBluetooth, CoreBluetooth permission) |
| `Weather.swift` | Open-Meteo forecast + city search, `TemperatureUnit` |
| `Clock.swift`, `NotchFit.swift`, `Hotkeys.swift`, `HistoryStore.swift`, `NotificationLog.swift`, `SettingsBackup.swift`, `Intents.swift`, `Format.swift` | Clock formats/world clocks, notch fitting maths, global shortcuts, 1H/24H history file, notification history, settings export/import (key list!), Shortcuts actions, formatters (`Fmt`) |

## Monitors/ (one sampler each; no UI)

`CPUMonitor`, `GPUMonitor`, `MemoryMonitor`, `NetworkMonitor` (+ `NetworkAppSampler`: `nettop`), `DiskMonitor`,
`SensorsMonitor` (HID temps, private API) + `SMC`, `BatteryMonitor`, `DeviceBatteryMonitor` (Bluetooth
accessories via `system_profiler`), `ProcessSampler` (`ps`), `PortSampler` (`lsof`), `USBDeviceMonitor` (IOKit),
`AgentUsageMonitor` (parsers for Claude / Codex / Copilot / OpenCode logs, `RateWindow`, scanner, summaries).

## Views/

| File | What's in it |
|---|---|
| `MenuBarLabels.swift` | Every menu bar label (fixed widths!), `AgentLimitsLabel`, `ClaudeEstimateLabel` |
| `CombinedViews.swift` | Combined item, `AwakeCup`, `KeepAwakeItemLabel` |
| `DeckView.swift` | Deck home (header, keep-awake strip, quick toggles, tiles), tiles' spoken labels |
| `Panels.swift` | Detail panels per module, `ProcessList`, `ListeningPortsSection`, `USBDevicesSection` |
| `AgentsPanel.swift` | Agents detail: Now card, charts, agent cards, `LimitGauge`, `PaceBar`, `DailyBars` |
| `MetricChart.swift` | Detail charts (resampling, `SeriesShape`, scrubbing) |
| `SettingsView.swift` | Settings window: every pane, `ItemOptionsView`, `.settingsFooter()` |
| `KeepAwakeViews.swift` | Cup menu items, status strip, Keep Awake settings pane |
| `QuickTogglesView.swift`, `NotificationHistoryView.swift`, `VibeRing.swift`, `ClockPanel.swift`, `WeatherPanel.swift`, `Charts.swift` | as named |

## Tests/VibeCheckTests/

Swift Testing (`@Test`, `#expect`). Pure logic is tested with fixtures; anything touching the system (Keychain,
network, real processes, real files in `~`) is never run for real, except reading-only probes. Scanner tests
pass explicit empty locations (`claudeRoots`, `opencodeDB`, `claudeConfig`, …) so they never read the real home.

## scripts/

`render_brand.swift` (brand assets from `branding/svg`), `qa/` (on-screen QA tools: `scripts/qa/build.sh`,
then `.build/qa/qa help`).
