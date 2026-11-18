# VibeCheck improvement plan

A living log for future work sessions. **Read this first**, then add to it at the end of each session
(see [How to update this file](#how-to-update-this-file)).

_Last updated: 2026-11-18 · version 1.5 · 30 commits · ~6,800 lines of Swift · 64 tests_

---

## 1. Where things stand

VibeCheck is a native macOS (14+) menu bar system monitor: CPU, GPU, memory, network, disk, sensors,
battery, clock and weather, summed up by a **vibe score** (vibing / mid / cooked). Clicking the menu bar
item opens the **deck**, a Liquid Glass panel with live tiles that unfold into detail views. Settings is a
sidebar window with a live menu bar preview. Full feature list: [README](../README.md). Brand:
[branding/BRAND.md](../branding/BRAND.md).

**Installed** at `/Applications/VibeCheck.app` with launch at login on. The owner's setup: one combined
item, tight spacing, auto-fit around the notch capped at 2 stats (Memory, Network shown first).

### Verified vs. not verified

Development so far had **no screen recording permission**, so nothing has been looked at on screen.
What *was* verified: unit tests, real data via `--dump`, real window frames via `--deck-demo`, and logs.

| Area | Status |
|---|---|
| Data collectors (CPU, GPU, memory, network, disk, sensors, battery, devices, weather) | ✅ real values checked with `--dump` |
| Deck window size and position (open, unfold, fold, close; multi-display; notch geometry) | ✅ frames logged with `--deck-demo` |
| Alerts, history, charts resampling, vibe score, notch fit, settings backup, layout widths | ✅ unit tests |
| Login item registration | ✅ `--login-item status` reports enabled |
| Liquid Glass look, tile hover/press, unfold animation, ring bounce | ❌ never seen |
| Chart scrubbing, range morph, haptics, drag-to-adjust numbers | ❌ never touched |
| Global shortcuts actually opening the deck | ❌ key simulation was blocked |
| Notifications actually appearing (permission prompt, banner) | ❌ |
| Notch auto-fit on the built-in display | ⚠️ maths verified with real widths, not seen (menu bar was on the external display) |
| Settings sidebar window, live preview, drag-to-reorder in a grouped Form | ⚠️ window opens at 760×560, contents not seen |
| Launch at login across a real restart | ⚠️ registered, not rebooted |
| Keep awake: power assertion held (display / system type) and released | ✅ `pmset -g assertions` against the built app + a unit test reading `IOPMCopyAssertionsByProcess` |
| Keep awake: deck cup menu, status strip, menu bar cup, Settings pane | ❌ never seen |
| Keep awake triggers: plugged in and external display start a session | ✅ built app with launch arguments + `pmset -g assertions` (on AC with the MSI display attached) |
| Keep awake: trigger ending on unplug / display removal, end notification, ⌃⌥⌘A, "Until" menu | ❌ not exercised (logic covered by unit tests) |
| App Intents metadata in the bundle (5 actions, 2 enums, 4 phrases) | ✅ `extract.actionsdata` inspected; signature verifies |
| CPU / memory with the deck closed: ~3.3% / ~100 MB installed (was ~3.9% / 138–155 MB) | ✅ installed app measured 3× 40 s with `ps`; `sample` shows our tick at ~70 ms per 20 s vs ~250 ms SwiftUI layout |
| Deck home / CPU / Sensors views after the throttling (process list, all-sensor list) | ❌ never seen |
| Notification history: cap, newest first, unseen count, persistence, alerts recorded | ✅ unit tests |
| Notification history: bell, red dot, popover in the deck | ❌ never seen |
| Shortcuts app lists the 5 VibeCheck actions | ✅ seen by the owner after installing (2026-11-18) |
| Running the actions; Spotlight / Siri phrases | ❌ not tried yet |
| Agents: Claude Code / Codex token totals from real logs | ✅ `--dump` (today's Claude total matched an independent Python count) + unit tests |
| Agents: menu bar item, tile, detail panel | ❌ never seen |

---

## 2. Backlog

Priorities: **P0** do next · **P1** soon · **P2** nice to have · **P3** someday / risky.

### P0: On-screen QA pass

Needs Screen Recording permission for the terminal or Claude (System Settings → Privacy & Security →
Screen & System Audio Recording), or the owner checking by hand. Walk through:

- [ ] Menu bar: combined item on the external display (all stats) and on the built-in display (ring, Memory, Network, "+N")
- [ ] Deck: glass look in light and dark mode, tile hover and press, unfold/fold, Esc, arrow keys, ⌘1–9
- [ ] Detail views: hero numbers, Details toggle, chart scrubbing bubble, peak haptic, Live/1H/24H morph
- [ ] Vibe ring: colors and bounce (force "mid" by running a CPU-heavy task for 30 s+)
- [ ] Settings: sidebar, live preview, drag to reorder, alert sentence tokens, number drag, banner preview
- [ ] Alerts: "Send Test Notification" shows a banner after allowing notifications
- [ ] Global shortcuts ⌃⌥⌘1–9 from another app
- [ ] Reduce Motion and Increase Contrast on: everything still readable, springs become fades
- [ ] VoiceOver: tiles read as sentences, alert number is adjustable

Fix whatever turns up before starting new features.

### P1

- **Performance: what's left is macOS, not VibeCheck.** Installed app idles at ~3.3–3.8% CPU, ~100 MB.
  Investigated 2026-11-18: almost all of it is `NSStatusItem _updateReplicants`, AppKit redrawing the
  status item's copy for each display's menu bar (~30 ms per display per redraw). On this macOS that
  path runs through AppKit's own `NSHostingView`, even when the button holds a plain image, and the cost
  is the same at a 5 s refresh as at 2 s, so redraws aren't driven by our ticks. Don't retry: rendering the
  label to an image (made it worse) or slowing the refresh (no change). Worth checking only if it grows:
  whether it scales with the number of displays, and on a future macOS.
- **Distribution.** Developer ID signing + notarization (`notarytool`), a DMG, and an update mechanism
  (Sparkle or a GitHub Releases check). Today it's ad hoc signed, so other Macs need right-click → Open.
- **Swift 6 language mode.** The package uses tools 5.10 / language mode 5. Turn on strict concurrency
  and fix warnings (most code is already `@MainActor`; samplers hop through `DispatchQueue.global`).
- **Separate-items reorder.** Moving modules in Settings doesn't move existing separate items (macOS keeps
  autosaved positions). Either document ⌘-drag (done in the UI) or recreate items with new autosave names.

### P2

- **Liquid Glass `.icon`** made in Icon Composer from `branding/svg/icon.svg` layers (keep the `.icns`
  for macOS 14–15).
- **WidgetKit widgets:** vibe ring, CPU/memory sparkline (needs an app group to share samples).
- **Network:** public IP (opt-in, privacy note), Wi-Fi details (SSID needs Location permission),
  per-app traffic history.
- **Battery:** charge history over days, health trend.
- **Localization:** strings are inline English; move to a String Catalog.
- **Agents module, next steps:** cost estimates (needs a maintained price table per model; don't guess
  prices), Claude's real plan limits (only available from Anthropic's API with the user's login; ask first),
  more agents (Gemini CLI, Cursor), an alert rule on tokens per hour, and a 7-day chart.
- **Keep awake, still open:** closed-lid mode needs root (`pmset disablesleep`); treat it like fan control
  (P3, owner sign-off). Other ideas: a schedule trigger (weekdays 9–5), "while on Wi-Fi X" (SSID needs
  Location permission), and a "while downloads are active" trigger using network rate.
- **Website / landing page** from the brand assets.
- **GitHub social preview:** upload `branding/png/social-card.png` in repo settings (manual; no API).

### P3 (risky or large)

- **Fan control.** Needs a privileged helper (`SMAppService.daemon`) writing SMC keys; a bug can affect
  cooling. Only with explicit owner sign-off and a hard safety floor.
- **iCloud settings sync** (NSUbiquitousKeyValueStore); watch for conflicts with per-Mac settings like
  notch fit.

### Tech debt

- `Sources/VibeCheck/Views/Panels.swift` is large; split per module.
- `AppDelegate.runDeckDemo()` is debug code in the app target; move behind a `#if DEBUG` or a separate
  debug file.
- `AppSettings` keeps growing; consider grouping (menu bar, alerts, clock, weather) into sub-objects.
- `ClockFormatStyle` caches formatters in a `nonisolated(unsafe)` static; fine while only used on the main
  thread, worth a lock if that changes.
- Private / undocumented APIs (all looked up at runtime with fallbacks):
  `IOHIDEventSystemClient*` (temperatures), `responsibility_get_pid_responsible_for_pid` (app grouping),
  SMC keys `PSTR`/`PDTR`/`F0Ac`. Re-check after each macOS update.
- An old settings domain from the Pulse name, `local.pulse.monitor`, is still on the owner's Mac; safe to
  delete with `defaults delete local.pulse.monitor`.

---

## 3. Known limits (by design or by macOS)

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
| Notification history lives in `~/Library/Application Support/VibeCheck/notifications.json`, not in defaults, and isn't part of settings backup | It's history, not a setting (like `history.json`) |
| App Intents metadata is generated in `build.sh` with Xcode's `appintentsmetadataprocessor` | SwiftPM doesn't run it; needs Xcode installed (build warns and skips otherwise). Keep the protocol list in `build.sh` in sync if new intent kinds (entities, queries) are added |
| Intents run in the app and wait ~2.5 s after a cold launch | CPU and network rates need two samples |
| Agents module reads local logs only, no network, no credentials | Privacy; works offline; no keychain prompts |
| Agent totals include cache reads (as usage tools usually count them) | Numbers line up with the tool people already compare against; the breakdown is in Details |
| Agents is module 10; ⌘0 / ⌃⌥⌘0 open it | The number row has no "10"; `Module.shortcutKey` maps 1–9 then 0 |
| Keep awake uses an IOKit assertion, not a `caffeinate` child process | Released automatically if the app dies; visible in `pmset -g assertions` |
| Keep-awake sessions don't survive a restart; "Start a session when VibeCheck opens" covers that | Avoids a Mac that never sleeps after a forgotten session |
| Slang only for vibing / mid / cooked; alerts and errors stay plain | Brand voice (see BRAND.md §6) |

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
