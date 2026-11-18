# VibeCheck improvement plan

A living log for future work sessions. **Read this first**, then add to it at the end of each session
(see [How to update this file](#how-to-update-this-file)).

_Last updated: 2026-11-18 · version 1.5 · 44 commits · ~7,200 lines of Swift · 77 tests_

---

## 1. Where things stand

VibeCheck is a native macOS (14+) menu bar system monitor: CPU, GPU, memory, network, disk, sensors,
battery, clock and weather, summed up by a **vibe score** (vibing / mid / cooked). Clicking the menu bar
item opens the **deck**, a Liquid Glass panel with live tiles that unfold into detail views. Settings is a
sidebar window with a live menu bar preview. Full feature list: [README](../README.md). Brand:
[branding/BRAND.md](../branding/BRAND.md).

**Installed** at `/Applications/VibeCheck.app` with launch at login on. The owner's setup (as of the QA pass):
separate items, tight spacing, ring on; Memory, Disk and Clock off; notch cap 0 (as many as fit).

### Verified vs. not verified

Until the 2026-11-18 QA pass there was no screen recording permission. Now there is: capture single
VibeCheck windows with `screencapture -l <windowID>` (see the QA pass session notes for the helpers),
not the whole screen.

| Area | Status |
|---|---|
| Data collectors (CPU, GPU, memory, network, disk, sensors, battery, devices, weather) | ✅ real values checked with `--dump` |
| Deck window size and position (open, unfold, fold, close; multi-display; notch geometry) | ✅ frames logged with `--deck-demo` |
| Alerts, history, charts resampling, vibe score, notch fit, settings backup, layout widths | ✅ unit tests |
| Login item registration | ✅ `--login-item status` reports enabled |
| Deck look (dark mode), tiles, sparklines, keyboard focus ring | ✅ seen in the QA pass |
| Light mode, tile hover/press, unfold animation, ring bounce, mid/cooked colors | ❌ never seen |
| Chart scrubbing bubble (hover, values, "No data" gaps) | ✅ seen with synthetic mouse moves |
| Range morph, peak haptic, drag-to-adjust numbers | ❌ never touched |
| Deck keys: Esc (detail → home), arrows (focus ring), ⌘2 (opens GPU) | ✅ synthetic key events, logged + seen |
| Global shortcuts ⌃⌥⌘1–9 from another app | ❌ not tried |
| Notifications actually appearing (permission prompt, banner) | ❌ |
| Notch auto-fit on the built-in display | ⚠️ maths verified with real widths, not seen (menu bar was on the external display) |
| Settings: all 8 panes, live preview | ✅ seen |
| Settings: drag to reorder, number drag, token menus, banner preview | ❌ not touched |
| Launch at login across a real restart | ⚠️ registered, not rebooted |
| Keep awake: power assertion held (display / system type) and released | ✅ `pmset -g assertions` against the built app + a unit test reading `IOPMCopyAssertionsByProcess` |
| Keep awake: deck cup menu, menu bar cup, Settings pane | ✅ seen ("Until" submenu not opened: synthetic clicks don't open submenus) |
| Keep awake: status strip while a session runs | ❌ never seen |
| Keep awake triggers: plugged in and external display start a session | ✅ built app with launch arguments + `pmset -g assertions` (on AC with the MSI display attached) |
| Keep awake: trigger ending on unplug / display removal, end notification, ⌃⌥⌘A, "Until" menu | ❌ not exercised (logic covered by unit tests) |
| App Intents metadata in the bundle (5 actions, 2 enums, 4 phrases) | ✅ `extract.actionsdata` inspected; signature verifies |
| CPU / memory with the deck closed: ~3.3% / ~100 MB installed (was ~3.9% / 138–155 MB) | ✅ installed app measured 3× 40 s with `ps`; `sample` shows our tick at ~70 ms per 20 s vs ~250 ms SwiftUI layout |
| Deck home, CPU (process list), GPU, Battery views | ✅ seen |
| Network, Sensors (all-sensor list), Agents, Weather detail views | ❌ never seen |
| Swift 6 language mode: builds with zero warnings, tests pass, app runs (deck demo, keep awake, agents rescan) without runtime isolation crashes | ✅ `--deck-demo` + 80 s run, no crash reports |
| Notification history: cap, newest first, unseen count, persistence, alerts recorded | ✅ unit tests |
| Notification history: bell, popover empty state | ✅ seen |
| Notification history: red dot, list with entries | ❌ never seen |
| Shortcuts app lists the 5 VibeCheck actions | ✅ seen by the owner after installing (2026-11-18) |
| Running the actions; Spotlight / Siri phrases | ❌ not tried yet |
| Agents: Claude Code / Codex token totals from real logs | ✅ `--dump` (today's Claude total matched an independent Python count) + unit tests |
| Agents: menu bar item, tile | ✅ seen |
| Agents: detail panel | ❌ never seen |
| Bluetooth off while asleep: private calls resolve, permission read without prompting, `--dump` line | ✅ unit test + `--dump` |
| Bluetooth off while asleep: permission prompt, toggle and footer in Settings, actually off during sleep / on after wake | ❌ not tried (needs the owner to allow Bluetooth and sleep the Mac) |
| Quit / Force Quit: protection rules, start-time identity check, quitting a real child process | ✅ unit tests |
| Quit / Force Quit: right-click menu, inline confirmation, notice in the deck | ❌ never seen |
| Secure input: detection and app lookup with secure input really on | ✅ probe test (`EnableSecureEventInput`) |
| Secure input: warning in Settings → Shortcuts | ❌ never seen |

---

## 2. Backlog

Priorities: **P0** do next · **P1** soon · **P2** nice to have · **P3** someday / risky.
Re-prioritized 2026-11-18 after a review of [another app](https://github.com/otherapp/otherapp-utils), a
large menu bar toolkit with overlapping features. Items marked _(V)_ come from it. It's **GPL-3.0**: take
ideas, never code.

How the order was set: finish verifying what's shipped first, then features that reuse data VibeCheck
already collects, then new on-theme modules, and last anything that deletes files, needs root or private
hardware access.

### P0: Verify what's shipped

**On-screen QA pass** (remaining). Needs the owner to keep hands off the Mac (see "How to run it" below).

- [x] Menu bar: separate items on both displays (2026-11-18). Combined item + notch fit still not seen (owner uses separate items now)
- [ ] Deck: light mode, tile hover and press, unfold/fold animation (dark mode, Esc, arrows, ⌘2 done)
- [ ] Detail views: Network, Sensors, Agents, Weather; Details toggle, peak haptic, Live/1H/24H morph (CPU, GPU, Battery, scrubbing done)
- [ ] Vibe ring: colors and bounce (force "mid" by running a CPU-heavy task for 30 s+)
- [ ] Settings: drag to reorder, alert sentence tokens, number drag, banner preview (all panes + preview seen)
- [ ] Alerts: "Send Test Notification" shows a banner after allowing notifications
- [ ] Global shortcuts ⌃⌥⌘1–9 from another app
- [ ] Reduce Motion and Increase Contrast on: everything still readable, springs become fades
- [ ] VoiceOver: tiles read as sentences, alert number is adjustable

**Bluetooth off while asleep** (owner will test): turn it on in Settings → General, allow the Bluetooth
prompt, sleep and wake, then check the log (command in the session history entry).

- [ ] Permission prompt appears when the toggle is switched on
- [ ] "Bluetooth off for sleep" and "Bluetooth back on (wake)" in the log; Bluetooth really back on

Fix whatever turns up before starting new features.

How to run the QA pass (learned 2026-11-18): the owner must keep hands off the mouse and keyboard.
Synthetic clicks and keys go wherever focus is, the deck closes whenever another app activates (correct
behaviour), and a full-screen app on a display hides that display's menu bar, so clicks land in the app.
Before sending any key, confirm the deck window is on screen (layer 101 in `CGWindowListCopyWindowInfo`).
Synthetic clicks don't open menu submenus.

### P1: Reuse what VibeCheck already knows

1. ~~Kill process~~ _(V)_: done 2026-11-18 (`99b292e`, `7a0edf9`). Still open: "kill the process tree"
   (children of a CLI process), and seeing the menu and confirmation on screen.
2. ~~Secure input warning~~ _(V)_: done 2026-11-18 (`cd4159a`). Still open: a hint in the deck when a global
   shortcut is pressed but blocked, and seeing the Settings warning on screen.
3. **Agents: plan limits and cost** _(V)_, replacing the old "Agents module, next steps":
   - Codex already reports rate limits in its logs; show the 5-hour and weekly percentages with reset times.
   - Claude plan limits only come from Anthropic with the user's login; ask the owner before reading any
     credential, and keep it opt-in.
   - API-equivalent cost: another app keeps prices in a JSON file in its repo, fetched at runtime, so prices
     can change without a release. Do the same (our own file, cached, with a "prices as of" date).
     Never hard-code prices.
   - More agents: OpenCode, GitHub Copilot, Gemini CLI. Also "in progress now" (a session written in the
     last minute), a tokens-per-hour alert rule, and a 7-day chart.
4. **Port manager** _(V)_. Listening TCP ports with the owning process (`lsof -nP -iTCP -sTCP:LISTEN`, only
   while the view is open), in the Network detail view; kill through item 1.
5. **Distribution.** Developer ID signing + notarization (`notarytool`), a DMG, an update check (Sparkle or
   GitHub Releases), and a Homebrew cask _(V)_. Today it's ad hoc signed, so other Macs need right-click → Open.
6. **Separate-items reorder.** Moving modules in Settings doesn't move existing separate items (macOS keeps
   autosaved positions). Either document ⌘-drag (done in the UI) or recreate items with new autosave names.

### P2: New, on-theme

- **Accessory battery alert** _(V)_: notify once when a Bluetooth device drops to 20% (the batteries are
  already read). Add it as an alert metric so the threshold is editable.
- **Connected USB devices** _(V)_: a count and list in the Battery panel's Devices section (IOKit `IOUSBHostDevice`).
- **Fully unload switched-off modules** _(V)_: check every monitor stops sampling when its module is off,
  not just hidden. Measure before/after with `ps`.
- **Timer, stopwatch, focus sessions** _(V)_, tied to keep awake: a focus session keeps the Mac awake until it ends.
- **Downloads watcher** _(V)_: files arriving in a chosen folder; enables a "while downloads are active"
  keep-awake trigger.
- **Quick toggles** _(V)_: a row in the deck: dark mode, mute microphone, empty Trash (with confirm).
- **Keep awake, other triggers:** a schedule (weekdays 9–5), "while on Wi-Fi X" (SSID needs Location permission).
- **WidgetKit widgets:** vibe ring, CPU/memory sparkline (needs an app group to share samples).
- **Network:** public IP (opt-in, privacy note), Wi-Fi details (SSID needs Location permission),
  per-app traffic history.
- **Battery:** charge history over days, health trend.
- **Localization:** strings are inline English; move to a String Catalog.
- **Liquid Glass `.icon`** made in Icon Composer from `branding/svg/icon.svg` layers (keep the `.icns`
  for macOS 14–15).
- **Website / landing page** from the brand assets.
- **GitHub social preview:** upload `branding/png/social-card.png` in repo settings (manual; no API).

### P3 (risky or large)

- **Fan control.** Needs a privileged helper (`SMAppService.daemon`) writing SMC keys; a bug can affect
  cooling. another app ships one (manual RPM and temperature curves), which shows it's workable. Only with
  explicit owner sign-off and a hard safety floor.
- **Disk cleaner** _(V)_: start read-only (show reclaimable caches and leftovers in the Disk view); deleting
  needs a review step and never touches user documents.
- **Display brightness** _(V)_: per-display sliders; external monitors need DDC over private APIs.
- **Calendar** _(V)_: month view and upcoming events in the Clock panel; needs calendar permission and
  widens the app's scope.
- **Keep awake with the lid closed:** needs root (`pmset disablesleep`); same sign-off as fan control.
- **iCloud settings sync** (NSUbiquitousKeyValueStore); watch for conflicts with per-Mac settings like
  notch fit.

Not planned: another app's window, Dock, mouse, keyboard, clipboard, file, screenshot, recording, uninstaller,
lyrics and companion tools, and its notch-style "Dynamic Island" bar. They're outside a system monitor.

### Tech debt

- `Sources/VibeCheck/Views/Panels.swift` is large; split per module.
- `AppDelegate.runDeckDemo()` is debug code in the app target; move behind a `#if DEBUG` or a separate
  debug file.
- `AppSettings` keeps growing; consider grouping (menu bar, alerts, clock, weather) into sub-objects.
- `ClockFormatStyle` caches formatters in a `nonisolated(unsafe)` static; fine while only used on the main
  thread, worth a lock if that changes.
- Private / undocumented APIs (all looked up at runtime with fallbacks):
  `IOHIDEventSystemClient*` (temperatures), `responsibility_get_pid_responsible_for_pid` (app grouping),
  SMC keys `PSTR`/`PDTR`/`F0Ac`, `IOBluetoothPreference{Get,Set}ControllerPowerState` (Bluetooth sleep).
  Re-check after each macOS update.
- An old settings domain from the Pulse name, `local.pulse.monitor`, is still on the owner's Mac; safe to
  delete with `defaults delete local.pulse.monitor`.

---

## 3. Known limits (by design or by macOS)

- Idle cost is mostly macOS: the installed app idles at ~3.3–3.8% CPU, ~100 MB, and almost all of it is
  `NSStatusItem _updateReplicants` (AppKit redrawing each display's copy of the status items, ~30 ms per
  display per redraw, through AppKit's own `NSHostingView`). Same cost at a 5 s refresh as at 2 s.
  Don't retry rendering the label to an image (worse) or slowing the refresh (no change). Re-check on a
  future macOS, and whether it scales with the number of displays.
- Battery temperature isn't exposed on the owner's Mac (row hides itself).
- Logitech devices (e.g. MX Master) don't report battery to macOS.
- Status item windows are taller than the menu bar on some displays; the deck anchors to the button's
  on-screen rect, not its window (see `DeckController.targetFrame`).
- With separate items and a full menu bar, macOS hides some items; the combined item + notch fit is the fix.
- `nettop` takes ~1 s per sample, so per-app network data lags by a second and only runs while the
  Network detail view is open.
- Weather needs network access to Open-Meteo; only the chosen city's coordinates are sent.

---

## 4. Decisions log

Short record of choices future sessions shouldn't silently undo.

| Decision | Why |
|---|---|
| Swift Package + `build.sh` instead of an Xcode project | Simple, scriptable, no project file churn |
| `LSUIElement` accessory app, AppKit status items + SwiftUI views | Menu bar only; SwiftUI for UI, AppKit for windows and status items |
| One shared `DeckPanel` (borderless non-activating `NSPanel`) instead of `NSPopover` | Smooth resize, matched-geometry transitions, no arrow, one window for every item |
| Glass on the deck only, quiet fills on tiles | Apple's guidelines say not to stack glass on glass |
| Menu bar monochrome by default, color only when not vibing | macOS menu bar conventions |
| Vibe state needs 2 consecutive samples to change | Prevents menu bar flicker |
| `ps` / `nettop` only run while a view needs them | CPU budget |
| Charts resample every range to 120 buckets | Lets Live/1H/24H morph with one animatable shape |
| Open-Meteo + city search, no Location permission | Free, no API key, privacy |
| Combined item is the default for new installs; existing choices kept | Fits notched MacBooks; never override a user's choice |
| Notch fit fills from the user's module order, optional cap | Owner wanted exactly Memory + Network beside the notch |
| Brand assets generated from SVG by `scripts/render_brand.swift` | One source of truth; `NSImage` renders SVG natively, no extra tools |
| Keep-awake triggers are edge-triggered; a manual session always wins | A Stop by hand sticks until the condition goes away and comes back; triggers never cut short a session the user started |
| Trigger endings don't notify; time-up, app-quit and low-battery endings do | Unplugging is something the user just did; the others happen behind their back |
| Temperatures are read at most every 4 s and only the SoC dies (24 of 45 channels) unless the Sensors panel is open | Each HID channel costs ~0.7 ms; the menu bar, vibe and alerts only use the hottest die |
| `ps` runs every 5 s on the deck home, every tick in CPU/Memory details, never with the deck closed (list is dropped) | The verdict only needs the loudest app; LaunchServices name lookups only for the top results |
| Agents: full folder walk every 5 min (and when the panel opens); in between, `stat` known files and read only growth | The walk was most of the scan cost; `URL.resourceValues` is cached per URL, so use `stat` |
| Swift 6 language mode (tools 6.0) | Strict concurrency is now a compile error; keep new main-thread state `@MainActor` and hop with `DispatchQueue.main.async { MainActor.assumeIsolated { … } }` from callbacks |
| Notification history lives in `~/Library/Application Support/VibeCheck/notifications.json`, not in defaults, and isn't part of settings backup | It's history, not a setting (like `history.json`) |
| App Intents metadata is generated in `build.sh` with Xcode's `appintentsmetadataprocessor` | SwiftPM doesn't run it; needs Xcode installed (build warns and skips otherwise). Keep the protocol list in `build.sh` in sync if new intent kinds (entities, queries) are added |
| Intents run in the app and wait ~2.5 s after a cold launch | CPU and network rates need two samples |
| Agents module reads local logs only, no network, no credentials | Privacy; works offline; no keychain prompts |
| Agent totals include cache reads (as usage tools usually count them) | Numbers line up with the tool people already compare against; the breakdown is in Details |
| Agents is module 10; ⌘0 / ⌃⌥⌘0 open it | The number row has no "10"; `Module.shortcutKey` maps 1–9 then 0 |
| Keep awake uses an IOKit assertion, not a `caffeinate` child process | Released automatically if the app dies; visible in `pmset -g assertions` |
| Keep-awake sessions don't survive a restart; "Start a session when VibeCheck opens" covers that | Avoids a Mac that never sleeps after a forgotten session |
| Slang only for vibing / mid / cooked; alerts and errors stay plain | Brand voice (see BRAND.md §6) |
| Bluetooth sleep: never touch Bluetooth at shutdown; only re-enable what VibeCheck turned off | Unlike similar Bluetooth tools: a Mac shouldn't boot with Bluetooth off, and a user's own "off" must stick |
| Every IOBluetooth power call is guarded by `CBManager.authorization == .allowedAlways` | Without Bluetooth permission macOS aborts the process (TCC); the prompt is shown when the toggle is switched on, never at sleep |
| another app (GPL-3.0) is a source of ideas only, never code | Copying GPL code would make VibeCheck GPL |
| Quit actions hold the pid's start time and refuse if it changed | pids are reused; a stale menu must never signal a different process |
| Secure input warning says where macOS "points", not who holds it | `kCGSSessionSecureInputPID` records the frontmost app when secure input starts (a CLI tool's was reported as Chrome, then Slack) |
| Agent prices come from a fetched price file with a date, never hard-coded | Prices change; a stale built-in table would show wrong costs |
| Settings footers use `settingsFooter()` (caption, leading) | Grouped `Form` footers align trailing by default on macOS |
| Chart areas add points with `addLine`, never `addLines` | `addLines` starts a new subpath and breaks the closed fill |

---

## 5. How to work on this project

```bash
./build.sh                       # build/VibeCheck.app
./build.sh --install             # also replaces /Applications/VibeCheck.app (quit the running copy first)
swift test                       # all tests
.build/debug/VibeCheck --dump    # one sample from every monitor (after swift build)
build/VibeCheck.app/Contents/MacOS/VibeCheck --deck-demo   # logs deck/settings window frames + notch fit
/Applications/VibeCheck.app/Contents/MacOS/VibeCheck --login-item status
swift scripts/render_brand.swift # regenerate icon and brand assets from branding/svg
```

- Settings live in the `local.vibecheck.app` defaults domain; history in
  `~/Library/Application Support/VibeCheck/history.json`.
- Work on `main` (the owner chose that); conventional commit messages; **no Claude attribution** in
  commits or PRs.
- Repo: `saroj-shahi/vibecheck` (private).
- When changing settings on the owner's Mac for testing, **save and restore their exact values**
  (a past session briefly dropped their Clock and Battery items by restoring an outdated list).

---

## 6. Session history

### 2026-11-18: from zero to 1.5 (one long session)

| Commit | What |
|---|---|
| `baca80f` | First version ("Pulse"): CPU, memory, network, disk, battery, then GPU and sensors (HID temps, SMC fans/power) |
| `6eae65a` | Renamed to **VibeCheck**; private GitHub repo |
| `e1cab66` | Batch 1: combined item, alerts, hour/day history, global shortcuts |
| `ef51b08` | Batch 2: Bluetooth device batteries, app grouping, label styles, clock + world clocks |
| `795064a` | Network activity indicators, spacing setting, measured item widths |
| `c7bcb36` | Batch 3: per-interface and per-app network, weather (Open-Meteo), settings backup |
| `e4c4b07` | Redesign phase 1: deck panel, live tiles, unfold transition, keyboard |
| `22c8b9c` | Redesign phase 2: three-tier detail views, chart scrubbing, range morph |
| `cb47716` | Redesign phase 3: vibe score and ring, sentence alerts, sidebar settings |
| `80f60dd` | Fix: deck opened at the top-right on multi-display setups |
| `b835bab` | Auto-fit the combined item around the camera notch |
| `d5cd27f` | Cap stats beside the notch (owner set 2) |
| `fd57c80` | `--login-item` option; installed to /Applications with launch at login |
| `73d933f` | App icon, brand system, README refresh |

Bugs found and fixed along the way: deck window collapsing to 10×10 (content-derived window sizing),
deck placement before the status item exists, deck at the screen corner on multi-display setups (status
item windows taller than the menu bar), a stale close-fade hiding a reopened deck, `%` in log format
strings, clipped mark in the lockup.

### 2026-11-18: network status dot

| Commit | What |
|---|---|
| `dbda3a7` | Green/red status dot on the network glyph: menu bar (icon + value style and the offline glyph), deck tile and panel header (`NetworkStatusDot` in `MenuBarLabels.swift`). |

Notes: builds and `swift test` passes; installed and the green dot was seen in the menu bar (icon + value style) via a screenshot. Red (offline), deck tile and panel header not yet seen on screen. Green = an interface is up, red = offline. The menu bar's standard (graph) style has no network icon, so no dot there.

### 2026-11-18: keep awake

| Commit | What |
|---|---|
| `6b6e8a1` | Keep awake, modeled on classic keep-awake apps: `KeepAwake.swift` (sessions + IOKit assertion), `KeepAwakeViews.swift` (deck cup menu, status strip, Settings pane), cup in the combined and standalone items, notch fit counts the cup, 5 tests. |

Notes: `swift test` passes (48). The built app was run with launch arguments (`-keepAwakeAtLaunch YES`, `-keepAwakeDisplayOn '<false/>'`), which don't touch saved settings; `pmset -g assertions` showed `PreventUserIdleDisplaySleep` / `PreventUserIdleSystemSleep` named "VibeCheck keep awake", gone after quitting. No UI was looked at on screen. Booleans passed as launch arguments must use plist syntax (`'<false/>'`), since the settings read them with `as? Bool`. With separate items, the standalone item now also appears (cup only) when the ring is off and a session runs.

### 2026-11-18: agent usage tracker

| Commit | What |
|---|---|
| `6a8eb9d` | Agents module: `AgentUsageMonitor.swift` (incremental reader for `~/.claude/projects` and `~/.codex/sessions`, dedupe, Codex running-total deltas and rate limits, usage tools-style 5-hour block), `AgentUsage.swift` (store, rescans every 60 s off the main thread), `AgentsPanel.swift`, menu bar label, tile, ⌘0 / ⌃⌥⌘0 shortcut, `--dump` line, 6 tests. |

Notes: `swift test` passes (54). Release build: first scan of a week of logs (~1.1 GB of Claude transcripts on the owner's Mac, only files changed in 7 days are read) took ~1 s; rescans ~30 ms since only new bytes are read. Today's Claude total matched an independent Python count. Nothing seen on screen. Agents is on by default, so it shows up for existing installs too (beyond the notch cap it lands in "+N").

### 2026-11-18: keep awake extras

| Commit | What |
|---|---|
| `36a9bae` | Stay awake until a time of day (deck "Until" menu with the next whole hours, Settings time picker), ⌃⌥⌘A toggle shortcut, notification when a session ends by itself (`AlertEngine.notify`), triggers: while plugged in / while an external display is connected (`AwakeTriggerAction`), Settings can be opened on a page (`SettingsRouter`), 2 tests. |

Notes: `swift test` passes (56). Both triggers started a session in the built app (verified with `pmset -g assertions`); with no triggers nothing was held. Unplugging, the notification banner, the shortcut and the menus weren't exercised. Testing tip: in zsh, put launch arguments directly on the command line; an unquoted `$args` variable is not split into words.

### 2026-11-18: Shortcuts actions (App Intents)

| Commit | What |
|---|---|
| `deaa7cc` | `Intents.swift`: Get Mac Vibe, Get Mac Stat (9 stats), Open VibeCheck Deck, Keep Mac Awake, Let Mac Sleep, plus Spotlight/Siri phrases. `build.sh` compiles with `-emit-const-values-path` and runs `appintentsmetadataprocessor` into `Contents/Resources/Metadata.appintents`. `AppDelegate.openDeck(_:)`. 2 tests. |

Notes: `swift test` passes (58). The metadata lists all 5 actions and 4 phrases, and the signed bundle verifies. After installing, the owner saw the actions in the Shortcuts app. Running them and the Spotlight/Siri phrases are not checked yet.

### 2026-11-18: notification history

| Commit | What |
|---|---|
| `b314ba8` | `NotificationLog` (last 20, newest first, seen marker, saved to Application Support); `AlertEngine` records fired alerts and keep-awake endings (`log`, `notify(kind:)`); bell button with red dot and a popover list in the deck header (`NotificationHistoryView.swift`). 4 tests. |

Notes: `swift test` passes (62). The deck UI wasn't seen on screen, and no real notification was triggered (that would have written a test entry into the owner's history). Test notifications from Settings aren't recorded.

### 2026-11-18: performance pass

| Commit | What |
|---|---|
| `a93e6b3` | Sensors: dies only and at most every 4 s unless the Sensors panel is open (`sensorDemand`). Processes: 5 s interval on the deck home, dropped when the deck closes, verdict only while the deck shows it, name lookups only for the top apps. Agents scan: `stat` before opening, full walk every 5 min, `autoreleasepool` per file. `--dump` prints sensor counts. 2 tests. |

Notes: VibeCheck's own tick work went from ~27 ms to ~4–6 ms per second (`sample`). Installed and measured with the deck closed: ~3.3% CPU and ~100 MB, down from ~3.9% and 138–155 MB. The first side-by-side test (2.65%) overstated it: the second copy's menu bar item was hidden for lack of room, so it skipped the SwiftUI drawing that is now the biggest cost (and the commit message quotes that 2.65%). Testing tip: compare builds one at a time, not side by side. Deck behaviour after the throttling wasn't looked at on screen.

### 2026-11-18: menu bar rendering investigation (no code change)

Tried replacing the hosted SwiftUI label in the status button with an image rendered by `ImageRenderer`
only when the pixels change. Installed and measured: 3.5–7% CPU (worse). `sample` still showed
`_redrawReplicantSnapshot` → `NSHostingView.layout`, so the replicant snapshots go through AppKit's own
SwiftUI regardless of the button's content. Observation tracking also can't see what `ImageRenderer`
reads. Reverted. Measured the committed build at 2 s vs 5 s refresh (launch argument, settings untouched):
3.80% vs 3.75%, so the remaining cost isn't tied to VibeCheck's update rate.

### 2026-11-18: Swift 6 language mode

| Commit | What |
|---|---|
| `e267d99` | `swift-tools-version:6.0`. Fixes: page size via `sysconf` instead of the global `vm_kernel_page_size`, `@MainActor` on `Deck.resizeCurve`, an explicit sensor filter closure (the ternary crashed the compiler's diagnostics), and `String(cBuffer:)` replacing deprecated `String(cString:)` on arrays. |

Notes: only four concurrency fixes were needed. Zero warnings; 64 tests pass. Built app: `--dump` readings normal (interface names and IP after the C-string change), `--deck-demo` ran open/unfold/fold/close/Settings, a keep-awake session took its assertion, and the app ran 80 s past an agents rescan with no crash. Swift 6 runtime isolation checks can still fire in paths not exercised (notification permission callback, Bluetooth device fetch); watch for crash reports.

### 2026-11-18: on-screen QA pass (first look at the UI)

| Commit | What |
|---|---|
| `f9db3ed` | Detail chart fill closed diagonally (`Path.addLines` drops the baseline move); regression test. |
| `18b4885` | Deck verdict on its own full-width line (was truncated); "Total" label on the CPU line; leading Settings footers; preview edge fade; no duplicate city subtitle; no "for instantly". |

Notes: screen recording now works. Seen: both menu bars (separate items), deck home, CPU / GPU / Battery
detail, scrubbing bubble, bell popover, cup menu, keyboard (Esc, arrows, ⌘2), all Settings panes. A debug
build logged `active=true key=true` on open, so activation is fine; earlier "Chrome is frontmost" readings
were the owner's clicks. The pass stopped early because the owner was using the Mac (input conflicts, see
P0). Not seen: Network / Sensors / Agents / Weather detail, light mode, animations, global shortcuts,
notifications, accessibility modes. After installing, only the Settings fixes were looked at again; the deck
header fix was seen in the debug build, the chart fix in the GPU chart there. Testing tip: in zsh,
`set -- $var` doesn't split words; use `${=var}`.

### 2026-11-18: Bluetooth off while asleep (from similar Bluetooth tools)

| Commit | What |
|---|---|
| `a1bafd5` | `BluetoothSnooze.swift`: off at `willSleep`, on at `didWake` only if we turned it off, stored marker repaired at launch, nothing at shutdown. Toggle + footer in Settings → General (off by default), `NSBluetoothAlwaysUsageDescription`, permission asked when switched on, `--dump` line, backup key, 3 tests. |

Notes: `swift test` passes (68), zero warnings, installed and running. A first version crashed `--dump` with a
TCC privacy abort: reading the controller state needs Bluetooth permission (and an Info.plist usage string),
so every call is now guarded. Not verified: the prompt, the Settings toggle on screen, and a real sleep/wake.
To check: turn it on, allow Bluetooth, sleep and wake, then
`log show --last 10m --predicate 'process == "VibeCheck" AND eventMessage CONTAINS "Bluetooth"'`
should show "Bluetooth off for sleep" and "Bluetooth back on (wake)". Same caveats as similar tools: a
Bluetooth keyboard or mouse can't wake the Mac, and Apple Watch unlock won't work while asleep.

### 2026-11-18: quit processes, secure input warning (agents in parallel)

| Commit | What |
|---|---|
| `99b292e` | `ProcessKiller.swift`: Quit / Force Quit from the CPU and Memory process rows (context menu, inline confirmation); protected: kernel_task, launchd, WindowServer, loginwindow, VibeCheck, other users. 3 tests. |
| `7a0edf9` | Review fixes: start-time identity so a reused pid is never signalled, confirmations expire after 20 s, cancellable notice, VoiceOver hint on protected rows. |
| `cd4159a` | `SecureInput.swift`: Settings → Shortcuts warns while secure keyboard entry blocks the shortcuts. 6 tests. |

Notes: worked with two background agents: a read-only reviewer on the quit commit (found the pid-reuse
gap) and a builder for the secure input warning in separate files, while the quit feature was finished
here. 77 tests pass, zero warnings, installed. Live probe: with secure input on, the lookup found the key
in `IOConsoleUsers`, but the pid named the frontmost app (Chrome, later Slack), not the CLI tool that
turned it on, so the wording is hedged. Nothing new was seen on screen.

---

## How to update this file

At the end of each session:

1. Tick or remove finished backlog items; add new ones with a priority.
2. Update the **Verified vs. not verified** table if anything was checked on screen.
3. Add any decision that a future session might be tempted to undo to the **Decisions log**.
4. Add a dated entry to **Session history** (template below) and bump the _Last updated_ line.

```markdown
### YYYY-MM-DD: short title

| Commit | What |
|---|---|
| `abc1234` | … |

Notes: what was verified, what wasn't, anything the next session should know.
```
