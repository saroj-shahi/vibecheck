# VibeCheck improvement plan

A living log for future work sessions. **Read this first**, then add to it at the end of each session
(see [How to update this file](#how-to-update-this-file)).

_Last updated: 2026-11-18 · version 1.5 · 87 commits · ~10,900 lines of Swift · 148 tests_

---

## 1. Where things stand

VibeCheck is a native macOS (14+) menu bar system monitor: CPU, GPU, memory, network, disk, sensors,
battery, clock and weather, summed up by a **vibe score** (vibing / mid / cooked). Clicking the menu bar
item opens the **deck**, a Liquid Glass panel with live tiles that unfold into detail views. Settings is a
sidebar window with a live menu bar preview. Full feature list: [README](../README.md). Brand:
[branding/BRAND.md](../branding/BRAND.md). Design direction (deck layout, materials, micro-interactions,
⌘K): [DESIGN_DIRECTION.md](DESIGN_DIRECTION.md).

**Installed** at `/Applications/VibeCheck.app` with launch at login on. The owner's setup (as of the QA pass):
separate items, tight spacing, ring on; Memory, Disk and Clock off; notch cap 0 (as many as fit).

### Verified vs. not verified

Until the 2026-11-18 QA pass there was no screen recording permission. Now there is: capture single
VibeCheck windows with `screencapture -l <windowID>` (helpers in `scripts/qa`, tips in section 6),
not the whole screen.

| Area | Status |
|---|---|
| Data collectors (CPU, GPU, memory, network, disk, sensors, battery, devices, weather) | ✅ real values checked with `--dump` |
| Deck window size and position (open, unfold, fold, close; multi-display; notch geometry) | ✅ frames logged with `--deck-demo` |
| Alerts, history, charts resampling, vibe score, notch fit, settings backup, layout widths | ✅ unit tests |
| Login item registration | ✅ `--login-item status` reports enabled |
| Deck look (dark mode), tiles, sparklines, keyboard focus ring | ✅ seen in the QA pass |
| ⌘K command palette (search row, rows, selection, key caps) and the header search button, dark + light | 🟡 offscreen renders only (2026-11-18); typing, ↑↓/↩, hover chevron and the pre-26 hairline not seen live |
| Deck shell round two (search field, footer, ⌘↩ action card, 104 pt tiles), dark + light | 🟡 offscreen renders only (2026-11-18); live chips, culprit outline, 1× hairline and ⌘↩ keys not seen at all |
| Ring mid (yellow) and cooked (red) in the menu bar, "Cooked" verdict in the deck | ✅ seen 2026-11-18 (7 then 10 busy `yes` loops; mid after ~45 s) |
| Light mode, tile hover/press, unfold animation, ring bounce | ❌ never seen |
| Chart scrubbing bubble (hover, values, "No data" gaps) | ✅ seen with synthetic mouse moves |
| Range morph, peak haptic, drag-to-adjust numbers | ❌ never touched |
| Deck keys: Esc (detail → home), arrows (focus ring), ⌘2 (opens GPU) | ✅ synthetic key events, logged + seen |
| Global shortcuts ⌃⌥⌘1–9 from another app | ✅ ⌃⌥⌘2 opened GPU (QA round 2); others not tried |
| Notifications actually appearing | ✅ "Send Test Notification" banner seen by the owner; permission prompt not seen |
| Notch auto-fit on the built-in display | ⚠️ maths verified with real widths, not seen (menu bar was on the external display) |
| Settings: all 8 panes, live preview | ✅ seen |
| Settings: drag to reorder, number drag, token menus, banner preview | ❌ not touched |
| Launch at login across a real restart | ⚠️ registered, not rebooted |
| Keep awake: power assertion held (display / system type) and released | ✅ `pmset -g assertions` against the built app + a unit test reading `IOPMCopyAssertionsByProcess` |
| Keep awake: deck cup menu, menu bar cup, Settings pane | ✅ seen ("Until" submenu not opened: synthetic clicks don't open submenus) |
| Keep awake: status strip while a session runs | ✅ seen 2026-11-18 ("Staying awake until you stop it" + Stop) |
| Keep awake triggers: plugged in and external display start a session | ✅ built app with launch arguments + `pmset -g assertions` (on AC with the MSI display attached) |
| Keep awake "while files are downloading": a `.crdownload` in a watched folder takes the assertion in ~8 s; renaming it (download done) releases it | ✅ built app with launch arguments + `pmset -g assertions`, scratch folder (2026-11-18) |
| Keep awake "on a schedule": a window around now takes the assertion; it's released when the window ends | ✅ built app with launch arguments + `pmset -g assertions` (2026-11-18) |
| Keep awake: trigger ending on unplug / display removal, end notification, ⌃⌥⌘A, "Until" menu | ❌ not exercised (logic covered by unit tests) |
| App Intents metadata in the bundle (5 actions, 2 enums, 4 phrases) | ✅ `extract.actionsdata` inspected; signature verifies |
| CPU / memory with the deck closed: ~3.3% / ~100 MB installed (was ~3.9% / 138–155 MB) | ✅ installed app measured 3× 40 s with `ps`; `sample` shows our tick at ~70 ms per 20 s vs ~250 ms SwiftUI layout |
| Deck home, CPU (process list), GPU, Battery views | ✅ seen |
| Network (+ listening ports), Sensors (all-sensor list), Agents detail views | ✅ seen in QA round 2; Weather not seen (module off) |
| Swift 6 language mode: builds with zero warnings, tests pass, app runs (deck demo, keep awake, agents rescan) without runtime isolation crashes | ✅ `--deck-demo` + 80 s run, no crash reports |
| Notification history: cap, newest first, unseen count, persistence, alerts recorded | ✅ unit tests |
| Notification history: bell, popover empty state | ✅ seen |
| Notification history: red dot, list with entries | ❌ never seen |
| Shortcuts app lists the 5 VibeCheck actions | ✅ seen by the owner after installing (2026-11-18) |
| Running the actions; Spotlight / Siri phrases | ❌ not tried yet |
| Agents: Claude Code / Codex token totals from real logs | ✅ `--dump` (today's Claude total matched an independent Python count) + unit tests |
| Agents: menu bar item, tile | ✅ seen |
| Bluetooth off while asleep: private calls resolve, permission read without prompting, `--dump` line | ✅ unit test + `--dump` |
| Bluetooth off while asleep: permission prompt, toggle and footer in Settings, actually off during sleep / on after wake | ❌ not tried (needs the owner to allow Bluetooth and sleep the Mac) |
| Quit / Force Quit: protection rules, start-time identity check, quitting a real child process | ✅ unit tests |
| Quit / Force Quit: right-click menu, inline confirmation, notice in the deck | ❌ never seen |
| Secure input: detection and app lookup with secure input really on | ✅ probe test (`EnableSecureEventInput`) |
| Secure input: warning in Settings → Shortcuts, "Shortcuts paused" line in the deck | ❌ never seen |
| Limits gauges in the deck | ✅ rendered offscreen with sample limits; not seen in the real deck |
| Live Claude limits: parsing, merge | ✅ unit tests with fixture JSON |
| Copilot CLI and OpenCode parsing, dedupe, SQLite read, scanner pass | ✅ unit tests + `--dump` on real data (both present; 0 tokens this week, which matches the files' dates) |
| Copilot cards and both quota gauges in the deck | ✅ seen in the QA pass |
| Copilot quota from an old session; daily totals, last hour, working-now rule, tokens-per-hour metric | ✅ unit tests + `--dump` (Copilot: chat 9.3% used, completions 2.5%) |
| 7-day chart | ✅ rendered offscreen; not seen in the real deck |
| Working-now badge, Now card, plan badges, limit gauges in the real deck | ✅ seen in the QA pass (tokens-per-hour alert not triggered) |
| Per-item options: content rules, decoding, migration of "Limits left" | ✅ unit tests; migration checked on the owner's real settings |
| Per-item options panel (Agents, Memory) | ✅ rendered offscreen through AppKit (`NSHostingView.cacheDisplay`, real controls); the slider button in the real Settings window seen, the expanded panel not |
| Live limits from Claude Code: real exchange from the app's code | ✅ probe test (0.9 s, plan "team") and the real menu bar item showed 9% / 61% left afterwards |
| Account/plan badges, Now card, Copilot's two quotas, per-day burn | ✅ rendered offscreen from real logs (AppKit, dark mode): "Claude Code · Saroj · Team", "Codex · Free", Now "VibeCheck · Opus 5.5 · 276K written" |
| Listening ports: `lsof -F` parsing | ✅ 7 unit tests (format checked against real `lsof` output) |
| Listening ports section | ✅ seen in the real deck (quit from it not tried) |

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
- [ ] Deck: light mode, tile hover and press, unfold/fold animation (dark mode, Esc, arrows, ⌘1/⌘2/⌘6/⌘0 done)
- [x] Detail views: Network (+ listening ports), Sensors, Agents, CPU Details toggle, Live/1H/24H (2026-11-18). Weather not seen (switched off); haptics and the morph animation can't be captured
- [ ] Vibe ring: bounce (colors seen 2026-11-18: yellow mid, red cooked; the loudest process was named "claude" because the load was spawned from it)
- [ ] Settings: drag to reorder (skipped: would change the owner's order), number drag, banner preview (all panes, item options panel, alert sentences seen)
- [x] Alerts: "Send Test Notification" shows a banner (owner saw it, 2026-11-18)
- [x] Global shortcuts: ⌃⌥⌘2 from another app opened GPU (2026-11-18)
- [ ] Reduce Motion and Increase Contrast on: everything still readable, springs become fades
- [ ] VoiceOver: tiles read as sentences ✅ (accessibility tree, 2026-11-18); alert number adjustable not checked; VoiceOver itself not run (system setting)

**Bluetooth off while asleep** (owner will test): turn it on in Settings → General, allow the Bluetooth
prompt, sleep and wake, then check the log (command under "Lessons" in section 6).

- [ ] Permission prompt appears when the toggle is switched on
- [ ] "Bluetooth off for sleep" and "Bluetooth back on (wake)" in the log; Bluetooth really back on

Fix whatever turns up before starting new features.

How to run the QA pass (learned 2026-11-18): the owner must keep hands off the mouse and keyboard.
Synthetic clicks and keys go wherever focus is, the deck closes whenever another app activates (correct
behaviour), and a full-screen app on a display hides that display's menu bar, so clicks land in the app.
Before sending any key, confirm the deck window is on screen (layer 101 in `CGWindowListCopyWindowInfo`).
Synthetic clicks don't open menu submenus.

### P1: Reuse what VibeCheck already knows

1. ~~Kill process~~ _(V)_: done 2026-11-18 (`99b292e`, `7a0edf9`). ~~Kill the process tree~~ done 2026-11-18:
   "Quit / Force Quit X and Subprocesses" for plain processes with children (tested with a throwaway shell).
   Still open: seeing the menus and confirmation on screen.
2. ~~Secure input warning~~ _(V)_: done 2026-11-18 (`cd4159a`). ~~Deck hint~~ done 2026-11-18: a blocked
   shortcut press never reaches the app, so the deck shows a "Shortcuts paused" line whenever it's open
   while secure input is on (click opens Settings → Shortcuts). Neither the deck line nor the Settings
   warning has been seen on screen.
3. **Agents: plan limits and cost** _(V)_:
   - ~~Limits UI~~ done 2026-11-18 (`3b8581d`): "% left" gauges with pace knob, burn per hour, reset countdown,
     "Limits left" stacked menu bar style.
   - ~~Claude's real limits~~ done 2026-11-18, opt-in in Settings → General. Now read from the user's own
     `claude` CLI (`get_usage`), no Keychain, no endpoint of our own (see Decisions log); real values seen in the
     menu bar. Settings status line not seen.
   - ~~API-equivalent cost~~: dropped 2026-11-18, the owner chose no costs (it would need a price-list download).
   - ~~More agents~~: GitHub Copilot CLI and OpenCode done 2026-11-18 (`0443c87`). Gemini CLI (only
     Antigravity settings on this Mac) and Cursor (usage kept on its servers) have no local token counts.
   - ~~Copilot quota from older sessions, "working now", tokens-per-hour alert, 7-day chart~~: done
     2026-11-18 (`1e6d8db`).
4. ~~Port manager~~ _(V)_: done 2026-11-18 (`ebd0ed8`), in the Network view. Section seen; quitting from it not tried.
5. **Distribution.** Developer ID signing + notarization (`notarytool`), a DMG, an update check (Sparkle or
   GitHub Releases), and a Homebrew cask _(V)_. On this Mac it's signed with the owner's free "Apple Development" certificate (Team ID `77HKFF78Z8`,
   expires Nov 2027; Xcode can renew it); other Macs still need Developer ID + notarization.
6. ~~Separate-items reorder~~: done 2026-11-18 (`536771f`). Not yet tried on the owner's menu bar (their current
   ⌘-dragged layout stays until they reorder in Settings).

### P2: New, on-theme

- ~~Accessory battery alert~~ _(V)_: done 2026-11-18 (`6341833`), as the "Accessory battery" alert metric.
- ~~Connected USB devices~~ _(V)_: done 2026-11-18 (`667cdf6`); not seen with a real device (none plugged in).
- **Fully unload switched-off modules** _(V)_: audited 2026-11-18, everything is still sampled when off. The costly
  one (accessory batteries via `system_profiler`) is now gated (`6341833`). The rest are cheap and feed the vibe
  score, alerts, keep awake and Shortcuts. Owner decided (2026-11-18): alerts and the vibe stay independent of
  which modules are shown, so these keep sampling. Done.
- ~~Focus sessions~~ _(V)_: done 2026-11-18 (`0d3e3ed`), in the cup menu. Stopwatch / free timer not built.
- ~~Downloads watcher~~ _(V)_: done 2026-11-18, as the "While files are downloading" keep-awake trigger
  (Settings → Keep Awake; watches ~/Downloads or a chosen folder). Seen working with the built app (see
  table). Not yet tried with a real browser download or on the real ~/Downloads (macOS asks for folder
  access the first time).
- ~~Quick toggles~~ _(V)_: done 2026-11-18 (`e51d9d5`). Never run for real yet: the first Dark or Trash tap asks for
  Automation permission (System Events / Finder); mic mute untested on hardware.
- **Keep awake, other triggers:** ~~a schedule~~ done 2026-11-18 ("On a schedule": days + hours, default
  weekdays 9–17, overnight windows belong to the start day; Settings rows not seen on screen). Still open:
  "while on Wi-Fi X" (SSID needs Location permission).
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

### Design direction (from [DESIGN_DIRECTION.md](DESIGN_DIRECTION.md))

- ~~⌘K command palette, type-to-act, tile hover chevron, glass hairline (macOS 14–15)~~: done 2026-11-18.
- **P1** See the palette live: ⌘K, typing on the home grid, ↑↓/↩, Esc twice (part of the P0 QA pass).
- ~~Round two: shell with search field, live chips, footer; 104 pt tiles; culprit outline; ⌘↩ actions~~: done 2026-11-18.
- **P1** See round two live: chips (keep awake, mic muted, shortcuts paused) with hover ×, culprit outline under load, ⌘↩.
- **P2** Keep-awake hold dial on the cup; pinned header while a detail view scrolls; palette "recent" ordering; process and alert commands.

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
| Agents module reads local logs only by default; live Claude limits (opt-in) ask the local `claude` CLI | Privacy; works offline; no Keychain access |
| Agent totals include cache reads (as usage tools usually count them) | Numbers line up with the tool people already compare against; the breakdown is in Details |
| Copilot input tokens are counted minus cache reads; OpenCode reasoning is counted as output | Copilot uses OpenAI-style counts (input includes cached); OpenCode reports reasoning separately. Keeps totals comparable across agents |
| OpenCode is read from its SQLite database read-only, only when the file or WAL changed | It has no log files; re-reading a week of rows is cheap and handles token counts filled in late |
| Agents is module 10; ⌘0 / ⌃⌥⌘0 open it | The number row has no "10"; `Module.shortcutKey` maps 1–9 then 0 |
| Keep awake uses an IOKit assertion, not a `caffeinate` child process | Released automatically if the app dies; visible in `pmset -g assertions` |
| Keep-awake sessions don't survive a restart; "Start a session when VibeCheck opens" covers that | Avoids a Mac that never sleeps after a forgotten session |
| Slang only for vibing / mid / cooked; alerts and errors stay plain | Brand voice (see BRAND.md §6) |
| Bluetooth sleep: never touch Bluetooth at shutdown; only re-enable what VibeCheck turned off | Unlike similar Bluetooth tools: a Mac shouldn't boot with Bluetooth off, and a user's own "off" must stick |
| Every IOBluetooth power call is guarded by `CBManager.authorization == .allowedAlways` | Without Bluetooth permission macOS aborts the process (TCC); the prompt is shown when the toggle is switched on, never at sleep |
| another app (GPL-3.0) is a source of ideas only, never code | Copying GPL code would make VibeCheck GPL |
| Quit actions hold the pid's start time and refuse if it changed | pids are reused; a stale menu must never signal a different process |
| Secure input warning says where macOS "points", not who holds it | `kCGSSessionSecureInputPID` records the frontmost app when secure input starts (a CLI tool's was reported as Chrome, then Slack) |
| Live Claude limits come from the user's own `claude` CLI (`get_usage` control request), never the Keychain or an Anthropic endpoint directly; opt-in, not in settings backup | Claude Code signs in and refreshes itself, so no Keychain prompts and no undocumented API; idea from another app (GPL: idea only, the protocol is Claude Code's) |
| "Limits left" shows Claude Code first: live limits, else its local estimate; other agents only without Claude Code | Falling back to Codex's monthly limit made Claude Code usage look missing (owner report) |
| "Limits left" has one fixed width (104 pt) in every state | Status item length is measured only at creation/settings changes; a growing label got clipped |
| `build.sh` signs with an "Apple Development" identity when present (then the self-signed "VibeCheck Local Signing", then ad hoc) | Keychain "Always Allow" on another app's item is stored in its partition list as `teamid:` for apps with a Team ID, but as `cdhash:` (one exact build) for apps without one, so self-signed and ad hoc builds re-prompt after every update. Don't drop the Apple Development identity |
| Per-item options live in `ItemOptions` (JSON per module, `itemOptions` key); the look stays in `LabelStyle` | Looks are shared across modules; options are module-specific and grow without new enum cases. Agents' icon follows the look picker, not an option |
| Account name and plan: Claude from `~/.claude.json` (`oauthAccount.displayName`, `organizationType`), Codex from `plan_type` in its logs; never `~/.codex/auth.json` | Only non-secret fields; credential files stay unread |
| `SIGPIPE` is ignored app-wide | Child processes (`ps`, `lsof`, `nettop`, `claude`) can exit before we write to them |
| Alerts and the vibe score don't depend on which modules are shown (owner, 2026-11-18) | A CPU alert should fire even with the CPU item hidden; so CPU, memory, disk, sensors and battery are always sampled. Only samples nothing else needs (accessory batteries) are gated |
| Keep Awake item: click toggles with the default length, right-click/⌃/⌥-click opens the menu (owner, 2026-11-18) | The owner wanted the default set in Settings and started by a click; the menu keeps the other options one click away |
| Quick toggles act through System Events / Finder / CoreAudio only; Trash is emptied by Finder, never by deleting files | The user's own undo and Finder's rules apply; Automation permission is asked on first use (`NSAppleEventsUsageDescription`) |
| ⌘K palette draws its query instead of using a TextField; keys come from the deck's key monitor | The deck is a non-activating panel that never takes focus from the user's app; a real field would need it to |
| Palette never offers Empty Trash or process kills; Quit needs a second ↩ | Type-to-act means "q" + Return would quit; Return in a list is too easy to hit by accident |
| A finished focus session always notifies | It's the point of a focus timer; other keep-awake endings follow the notify setting |
| Separate items' autosave names carry a generation (`vibecheck.cpu.g3`) bumped on each Settings reorder; generation 0 keeps the original names | macOS 27 remembers item positions by autosave name outside the app's defaults; new names are placed in creation order, each to the left (probe app). Don't revert to fixed names |
| Limit lists key on `RateWindow.key` (length + name) | Copilot's two monthly quotas share a length; keying on length drew one twice |
| Agents module: no network of its own; live Claude limits run the local `claude` CLI | Keeps "local logs only" true for VibeCheck itself |
| No cost estimates in the Agents module (owner, 2026-11-18) | It would need downloading a price list; never hard-code prices either |
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

Per-commit detail is in `git log`. Everything up to 2026-11-18 (v1.0 → 1.5, 80 commits) was folded into the
tables above and the lessons below; add new dated entries under "Recent sessions".

### Lessons and testing tips (still true)

- **Launch arguments override settings without touching them**: `-keepAwakeAtLaunch YES`; values read with
  `as? Bool` / `as? Int` need plist syntax (`'<false/>'`, `'<integer>540</integer>'`), or the default is used. In zsh put them on the command line; unquoted `$args` and
  `set -- $var` don't split words (use `${=var}`).
- **Measuring CPU**: compare builds one at a time, never side by side (a hidden second item skips the SwiftUI
  drawing that dominates the cost). Use `ps` over 40 s and `sample` for where time goes.
- **On-screen QA**: owner hands-off; drive buttons with `AXPress` / `AXSelected` (no focus needed; VibeCheck
  can't take focus from another app). Window captures show covered windows, but clicks land on whatever is on
  top. A cursor-moved guard (`PAUSE`) means the owner is using the Mac: stop. Synthetic clicks don't open submenus.
- **Offscreen renders**: use AppKit (`NSHostingView.cacheDisplay`) for real controls; `ImageRenderer` skips
  pickers and toggles.
- **Forcing vibe states**: 7 of 10 cores busy (`yes > /dev/null`) gives mid after ~45 s, 10 gives cooked. The
  verdict then names "claude" as loudest when the load is spawned from Claude Code (app grouping, not a bug).
- **Menu bar**: the notched built-in display shows fewer items than the external one, so accessibility
  listings vary with the active display. macOS 27 keeps item positions outside the app's defaults (see the
  autosave-generation decision); a probe app showed new names are placed in creation order.
- **Signing**: the Keychain "Always Allow" only survives rebuilds with a Team ID (`teamid:` in the partition
  list). The Apple Development cert needed Apple's WWDR G3 intermediate installed. The old "VibeCheck Local
  Signing" certificate is no longer needed.
- **Swift 6**: runtime isolation checks may still fire in paths not yet exercised (notification permission
  callback, Bluetooth device fetch); watch for crash reports.
- **Bluetooth sleep**: check with
  `log show --last 10m --predicate 'process == "VibeCheck" AND eventMessage CONTAINS "Bluetooth"'`
  (expect "Bluetooth off for sleep" / "Bluetooth back on (wake)"). While asleep a Bluetooth keyboard or mouse
  can't wake the Mac and Apple Watch unlock won't work.
- **Agents**: first scan of a week of Claude logs (~1.1 GB) takes ~1 s, rescans ~30 ms. Tests must pass empty
  locations, or they read the real home folder. Not bugs: "VibeCheck 2" briefly at 50% CPU is the Claude
  limits check (a child process).
- **Rejected**: rendering the status label to an image (worse CPU), reading the Claude token through
  `/usr/bin/security` (an "Always Allow" would cover every process that runs it).

### Recent sessions

#### 2026-11-18: design round two (outside reference)

Second pass of the Creative Director brief, using the owner's popover mockup
(`docs/otherapp-popover-mockup.html`, another app) for the shell. Header keeps only bell and cup; a drawn
search field is always visible; live chips replace the keep-awake and secure-input strips; a footer holds
Settings, version and Quit (key hints while the palette is open). Tiles are 104 pt (8 pt gutters), the
hover chevron is 10 pt and an overlay, the pre-26 hairline knows 1× displays, the vibe report names a
culprit module whose tile gets outlined, and ⌘↩ opens Run / Settings actions on a palette row. 4 tests.
Checked with offscreen renders (dark + light, home / palette / actions); chips and culprit not rendered.
Hold dial deferred (the cup is a SwiftUI `Menu`).

#### 2026-11-18: design direction + ⌘K palette

Ran the owner's "menu bar Creative Director" brief against the deck; result in
`docs/DESIGN_DIRECTION.md` (five sections, BRAND.md still wins). Built what it asked for that was missing:
⌘K palette (modules, keep awake, focus, Dark/Mic, every Settings pane, Quit), type-to-act on the home
grid, a search button in the header, a tile hover chevron (150 ms ease-out) and a 0.5 pt hairline on the
pre-Liquid Glass material. Checked with offscreen renders (`NSHostingView.cacheDisplay` in a throwaway
test), not live.

#### 2026-11-18: keep awake on a schedule

`AwakeSchedule` (days as weekday bits, start/end minutes) feeds the existing edge-triggered trigger, so a
Stop by hand inside the window sticks until the next window. Checked live with a 3-minute window. Settings
rows (day buttons, hours pickers) not seen on screen. Not sent for review: pure logic on the existing
trigger path, unit-tested.

#### 2026-11-18: downloads keep-awake trigger

`DownloadsWatcher` scans the folder's top level off the main thread at most every 5 s: active while a
browser in-progress file (`.crdownload`, `.download`, `.part`…) changed in the last 2 min, or any file in
the last 10 s. From review: a scan that was running when the setting/folder changed is ignored
(generation counter), and a scan stuck over 30 s (stalled network volume) counts as inactive. A project
hook blocks Bash commands that look destructive (deletes, even inside quoted text); split test steps,
avoid deletes, and finish a fake download by renaming it.

#### 2026-11-18: secure input hint in the deck

Carbon hot keys get no event at all while secure input is on, so "hint when a shortcut is pressed but
blocked" became a deck line shown while it's on (polled every 2 s, only while the deck home is visible and
shortcuts are enabled). `keyboard.badge.exclamationmark` doesn't exist on this macOS; check SF Symbols with
`NSImage(systemSymbolName:)` before using one. Not seen on screen.

#### 2026-11-18: kill the process tree

"and Subprocesses" menu items in the process and port lists (shared `QuitMenuItems`). The root is paused
(SIGSTOP) while its tree is taken, so supervisors can't respawn children; each child is signalled only if
it's still the child of the parent it was found under (pid reuse); protected children count as "still
running". Unit-tested only; menus not seen on screen. P0 QA still needs the owner hands-off.

#### 2026-11-18: QA round 3 (partial), plan cleanup

Ring seen yellow (mid) and red (cooked), plus the keep-awake strip. Stopped on PAUSE. Fixed stale table
rows and the old Keychain wording for Claude limits; folded the session history into the lessons above.

---

## How to update this file

At the end of each session:

1. Tick or remove finished backlog items; add new ones with a priority.
2. Update the **Verified vs. not verified** table if anything was checked on screen.
3. Add any decision that a future session might be tempted to undo to the **Decisions log**.
4. Add a short dated entry under **Recent sessions** (template below; commits are in `git log`) and bump the
   _Last updated_ line. When there are more than ~5, fold lasting lessons into the list above and drop the rest.

```markdown
#### YYYY-MM-DD: short title

What was verified and how, what wasn't, anything the next session should know.
```
