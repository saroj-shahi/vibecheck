# VibeCheck code map

Where things live, so a task can open the right file first. One line per file; keep it current when files
are added or split. Plans are in [ROADMAP.md](ROADMAP.md); design rules and decisions in [DEVELOPMENT.md](DEVELOPMENT.md).

## App/ (state, logic, system access)

| File | What's in it |
|---|---|
| `AppDelegate.swift` | `StatusItemController` (one menu bar item: kinds `.single(Module)`, `.combined`, `.vibe`, `.keepAwake`), `AppDelegate` (launch, `syncItems` / reorder rebuild by `statusItemGeneration`, deck/Settings opening, shortcuts) |
| `AppDelegate+DeckDemo.swift` | `--deck-demo` launch mode (logs item, deck and Settings frames); kept in release builds for QA |
| `AppSettings.swift` | `Module` enum (10 modules, order, symbols, label styles), `LabelStyle`, `Palette`, `AppSettings` (module-level settings, refresh, hotkeys, alerts; defaults domain `io.github.saroj-shahi.vibecheck`; groups below), `autosaveName` |
| `BundleIDMigration.swift` | One-time copy of settings from the pre-1.6 defaults domain `local.vibecheck.app`, run in `main.swift` before anything reads settings |
| `AppSettingsGroups.swift` | `SettingsWriter` (shared save helper) and the setting groups `settings.menuBar`, `.clock`, `.weather`, `.keepAwake` (same flat defaults keys as before the split) |
| `ItemOptions.swift` | Per-item menu bar options (Agents: which agents, % left/used/tokens, windows, reset; Memory, Network, Disk, Battery, Sensors) + `AgentUsageSample.menuBarContent` |
| `SystemStats.swift` | The tick: samples every monitor, histories, demand counters (`processDemand`, `networkAppDemand`, `sensorDemand`), vibe input, listening ports |
| `TickPolicy.swift` | `TickPolicy` (pause reasons + Low Power + keep awake → tick interval or none), `TickGate` (ring animation follows the pause) |
| `MenuBarVisibility.swift` | `DeckBackgroundKind` (glass / blur / opaque for Reduce Transparency), launch check that macOS isn't hiding every item |
| `AppMemoryHistory.swift` | Per-app memory footprint once a minute (libproc, no `ps`; grouped by responsible pid, keyed with start time), ~65 min of samples for the top 15 apps, `growth` for the verdict |
| `DevServers.swift` | `ListenerDetails` (cwd, start time, exe, footprint via libproc), dev-server classification, project name (nearest `.git` / `package.json` up to home), grouping, uptime text |
| `SleepDrain.swift` | Overnight drain: battery at sleep vs wake (≥ 2 h, on battery, ≥ 5 points), wake causes from one `pmset -g log` run, a 12 h report shown as one line on the deck home |
| `BluetoothConnectWatch.swift` | IOBluetooth connect / disconnect → accessory battery refresh (3 s debounce + 20 s re-read); `DeviceRefreshPolicy` (event-only, 10 min with an accessory alert, 60 s fallback without Bluetooth permission) |
| `IntentSnippets.swift` | `VibeSnippetView`: ring + verdict shown by the "How's my Mac's vibe?" intent |
| `Vibe.swift` | Vibe score (vibing / mid / cooked) with per-module enter / exit thresholds (`VibeThresholds`), swap and fast-drain signals, the verdict sentence and its culprit module |
| `Alerts.swift` | `AlertMetric`, `AlertRule` (sentence alerts), `AlertEngine` (evaluate, notify, history log); smart alerts (app memory leak, throttling ≥ 5 min, slow charger ≥ 5 min) with a 2 h per-culprit `AlertRateLimiter` |
| `KeepAwake.swift` | Sessions (`AwakeEnd`, focus sessions, triggers: power / display / downloads / `AwakeSchedule`), IOKit assertion |
| `CallGuard.swift` | Call detection (camera/mic in use via CoreMediaIO/CoreAudio), debounce, held alerts, heavy-app warning |
| `WiFiTrigger.swift` | Keep-awake "while on Wi-Fi X": CoreWLAN SSID, Location permission |
| `FocusFilter.swift` | `VibeCheckFocusFilter` (`SetFocusFilterIntent`: hold alerts, keep display awake), `FocusFilterStore` (persisted per Mac) |
| `RingDrop.swift` | `RingDropView` over the ring item's button: file / folder / app drops start keep awake (`.whileChanging` / `.whileRunning`), dilate while hovering |
| `VibeReplay.swift` | `VibeReplayStore`: 30-day log of mid / cooked episodes (culprit, worst level), `weeklySummary`, strip `segments` |
| `BatteryLog.swift` | `BatteryLogStore`: 90-day charge samples (every 15 min or 3% change) and daily health trend |
| `KeepAwakeMenu.swift` | Native keep-awake menu: the menu bar item's right-click and the deck's cup |
| `Deck.swift` | `DeckPanel` (borderless non-activating NSPanel), `DeckController` (open/close, frame, keys, outside clicks) |
| `AgentUsage.swift` | `AgentUsageStore` (rescans agent logs every 60 s, merges live Claude limits) |
| `ClaudeProfiles.swift` | Claude Code accounts: `ClaudeProfile` (default `~/.claude` or a `CLAUDE_CONFIG_DIR` folder; log roots, `.claude.json`, discovery of `~/.claude-*`), `ClaudeProfiles` (selected account, added folders; per Mac) |
| `ClaudeLimits.swift` | Live Claude limits from the user's `claude` CLI (`get_usage` control request); opt-in |
| `ProcessKiller.swift` | Quit / Force Quit (optionally with subprocesses) with protected processes and pid start-time identity |
| `QuickActions.swift` | Quick toggles: mic mute (CoreAudio), empty Trash (Finder) |
| `ClipboardHistory.swift` | `ClipItem`, `ClipboardHistory` (off by default: polls `changeCount` every 0.5 s, skips private types / Secure Input / ignored apps, optional `clipboard.json` at 0600; pinned snippets; copy and ⌘V paste), `AccessibilityAccess` (ask once per feature) |
| `CursorFinder.swift` | "Find my cursor": click-through ring panel at the pointer |
| `KeyboardCleaner.swift` | Keyboard cleaning mode: `CGEventTap` swallowing keys for 45 s, countdown overlay with Done |
| `SecureInput.swift` | Which app holds Secure Event Input (shortcuts paused) |
| `DeckCommands.swift` | ⌘K palette: the command list (incl. clipboard rows; "clip" narrows to them), ⌘↩ actions, and how typing filters it |
| `RecentCommands.swift` | Palette MRU (last 8 command ids, key `recentCommands`) |
| `AgentWatch.swift` | Agent runs from `AgentUsageStore`: working-now for the keep-awake trigger, long-run "is done" notification |
| `DownloadsWatcher.swift` | Whether files are arriving in the watched folder (keep-awake "while downloading" trigger) |
| `BluetoothSnooze.swift` | Bluetooth off while asleep (private IOBluetooth, CoreBluetooth permission) |
| `UpdateChecker.swift` | `UpdateChecker`: GitHub Releases check (`VCUpdateRepository` in Info.plist), version compare, 24 h throttle, one notification per version; injectable `fetch` |
| `StarPrompt.swift` | `StarPrompt`: one-time modal 2 days after first launch (keys `starPromptFirstSeen`, `starPromptShown`) asking for a GitHub star or a coffee |
| `Weather.swift` | Open-Meteo forecast + city search, `TemperatureUnit` |
| `Clock.swift`, `NotchFit.swift` (+ `NotchHideWatch`, notch auto-collapse), `Hotkeys.swift`, `HistoryStore.swift`, `NotificationLog.swift`, `SettingsBackup.swift`, `Intents.swift`, `Format.swift` | Clock formats/world clocks, notch fitting maths, global shortcuts, 1H/24H history file, notification history, settings export/import (key list!), Shortcuts actions, formatters (`Fmt`) |

## Monitors/ (one sampler each; no UI)

`CPUMonitor`, `GPUMonitor`, `MemoryMonitor`, `NetworkMonitor` (+ `NetworkAppSampler`: `nettop`), `DiskMonitor`,
`SensorsMonitor` (HID temps, private API) + `SMC`, `BatteryMonitor`, `DeviceBatteryMonitor` (Bluetooth
accessories via `system_profiler`), `ProcessSampler` (`ps`), `EnergySampler` (per-pid `ri_energy_nj` → estimated watts), `PowerReport` (IOReport "Energy Model" watts via `dlopen`, only while the CPU / GPU panel is open; CPU / ANE hidden when the OS zeroes them), `PortSampler` (`lsof` + `ListenerDetails`), `USBDeviceMonitor` (IOKit),
`NetworkExtras` (`WiFiReader` CoreWLAN, `PublicIPFetcher` opt-in api.ipify.org, `AppTrafficHistory` 1 h per app),
`AgentUsageMonitor` (parsers for Claude / Codex / Copilot / OpenCode logs, `RateWindow`, scanner, summaries).

## Views/

| File | What's in it |
|---|---|
| `MenuBarLabels.swift` | Every menu bar label (fixed widths!), `AgentLimitsLabel`, `ClaudeEstimateLabel` |
| `CombinedViews.swift` | Combined item, `AwakeCup`, `KeepAwakeItemLabel` |
| `DeckView.swift` | Deck shell (header, drawn search field, live chips, footer), home (quick toggles, tiles, culprit outline), tiles' spoken labels, glass hairline |
| `CommandPalette.swift` | ⌘K palette results, ⌘↩ action card, `KeyCap`, `Caret` |
| `Panels.swift` | Shared panel pieces: `Panel`, `PanelHeader` (pinned by `DeckRoot`), `StatRow`, `SectionTitle`, `DetailsDisclosure`, and `ModulePanel` (module to panel switch) |
| `ProcessList.swift` | `ProcessList` (CPU/memory top processes; app rows expand to their processes, 8 + "+N more"), quit/force-quit menu items, `ForceQuitConfirmRow` |
| `CPUGPUPanels.swift` | `CPUPanel`, `GPUPanel` |
| `MemoryPanel.swift` | `MemoryPanel` |
| `NetworkPanel.swift` | `NetworkPanel`, `ListeningPortsSection` (Dev servers group with Stop / Force stop, then other listeners) |
| `DiskPanel.swift` | `DiskPanel` |
| `SensorsPanel.swift` | `SensorsPanel` |
| `BatteryPanel.swift` | `BatteryPanel`, `DeviceBatteryRow`, `USBDevicesSection` |
| `AgentsPanel.swift` | Agents detail: Now card, charts, agent cards, `LimitGauge`, `PaceBar`, `DailyBars` |
| `AgentLogo.swift` | Agent logos (`AgentLogo`, `AgentLogoTile`, brand colors) from SVG path data, and `SVGPath` (small path-data parser) |
| `VibeStrip.swift` | `VibeStripView`: 24H / 7D / 30D vibe timeline from the episode log + weekly sentence (top of the CPU panel), day buckets split at midnight |
| `BatteryHistoryCharts.swift` | `BatteryHistorySection`: multi-day charge chart and health trend (Battery panel) |
| `RecoveryAndDrain.swift` | `RecoveryCheck` (cooked/mid to vibing, never on launch), `PulseCheckShape`, `CulpritDrain` (post-quit outline drain) |
| `DeckHintView.swift` | One dismissible what's-new line on the deck home after an update |
| `MetricChart.swift` | Detail charts (resampling, `SeriesShape`, scrubbing) |
| `SettingsView.swift` | Settings window: `SettingsSection` (sidebar groups, icons, search keywords), `SettingsRouter.open`, sidebar, Menu Bar / General / Backup / About / Support (Buy Me a Coffee) / Shortcuts pages, `.settingsFooter()` |
| `SettingsModules.swift` | One Settings page per module (`ModuleSettings`): on/off, menu bar options, the module's alerts, shortcut; Claude limits, Clock and Weather sections |
| `SettingsAlerts.swift` | Alerts page, `AlertRuleRow` (sentence alerts), token menus, `NumberToken`, `FlowLayout` |
| `ClipboardSettings.swift` | Settings → Clipboard: history on/off, length, keep across restarts, ignored apps, snippets, the "Paste from Other Apps" warning |
| `KeepAwakeViews.swift` | Deck cup (click → `KeepAwakeMenu`, hold → `AwakeDial`), Keep Awake settings pane |
| `QuickTogglesView.swift`, `NotificationHistoryView.swift`, `VibeRing.swift`, `ClockPanel.swift`, `WeatherPanel.swift`, `Charts.swift` | as named |

## Widgets (separate targets)

| File | What |
|---|---|
| `App/WidgetPublisher.swift` | Called on every tick: writes the widget snapshot into the app group once a minute while a widget is placed; reloads timelines on a vibe change |
| `Sources/VibeCheckShared/WidgetSnapshot.swift` | Library shared by app and widget: `WidgetSnapshot` (vibe, verdict, CPU / memory now and last hour), `WidgetShared` (app group `77HKFF78Z8.io.github.saroj-shahi.vibecheck`, read / write) |
| `Sources/VibeCheckWidget/VibeCheckWidgets.swift`, `WidgetViews.swift` | The WidgetKit extension: bundle, timeline provider (15 min), small "Vibe" ring and medium "CPU and Memory" sparklines |
| `Resources/Widget/` (`Info.plist`, `Widget.entitlements`), `Resources/VibeCheck.entitlements` | Appex plist and sandbox + app group entitlements; `build.sh` assembles `Contents/PlugIns/VibeCheckWidget.appex` (Apple Development identity only) |

## Tests/VibeCheckTests/

Swift Testing (`@Test`, `#expect`). Pure logic is tested with fixtures; anything touching the system (Keychain,
network, real processes, real files in `~`) is never run for real, except reading-only probes. Scanner tests
pass explicit empty locations (`claudeRoots`, `opencodeDB`, `claudeConfig`, …) so they never read the real home.

## packaging/

`homebrew/vibecheck.rb` (the Homebrew cask, to copy into the `saroj-shahi/homebrew-tap` repo as `Casks/vibecheck.rb`), `homebrew/README.md` (creating the tap and bumping the cask each release).

## scripts/

`render_dmg.swift` (the DMG install-window art in `branding/dmg/`: `share` with the Terminal step, `release` without), `render_ring_symbol.swift` (the vibe ring's custom SF Symbols in `Resources/Symbols.xcassets`, compiled into `Assets.car` by `build.sh`; `VibeRing` falls back to drawn shapes without it), `render_hero.swift` (the README hero `docs/screenshots/hero.png`: the deck screenshot on the brand gradient), `release.sh` (`--zip`: the public GitHub release, Apple Development signed with hardened runtime, `build/release/VibeCheck.zip` + `.sha256`, prints the cask lines and tag/`gh release` commands; no flag: Developer ID release, notarize + staple, DMG in `build/release/`; `--share` DMG for colleagues without Developer ID; lays out the branded DMG window through Finder and checks the saved layout), `install.sh` (the `curl … | bash` installer: downloads the latest release zip, checks its sha256, replaces `/Applications/VibeCheck.app` or `~/Applications`, clears quarantine, opens it; `--uninstall` keeps settings; `VIBECHECK_ZIP_URL` / `VIBECHECK_INSTALL_DIR` for testing), `extract_strings.sh` (refreshes `Sources/VibeCheck/Resources/Localizable.xcstrings` from the code; `build.sh` copies the compiled `en.lproj` into the app; `AppShortcuts.xcstrings` holds the Siri/Spotlight phrases, compiled by `build.sh` with `xcstringstool`), `render_brand.swift` (brand assets from `branding/svg`; the app icon from the render in `branding/art`); `branding/VibeCheck.icon` (Liquid Glass icon, compiled by `actool` in `build.sh`), `qa/` (on-screen QA tools: `scripts/qa/build.sh`,
then `.build/qa/qa help`).
