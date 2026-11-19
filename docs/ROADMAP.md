# VibeCheck roadmap

The one planning file for VibeCheck: what's next and in what order, what has shipped, what has been seen
working, the design rules and the decisions behind them. **Read sections 1 and 2 first**, then the rest
only for the area you're touching. Code locations are in [CODEMAP.md](CODEMAP.md); brand, voice and motion
in [BRAND.md](../branding/BRAND.md) (it wins over this file on those).

_Last updated: 2026-11-19 · version 1.5 · ~14,000 lines of Swift · 245 tests_

**Keeping it current (every session):** when a feature is done, move its row from §2 to §3 *Shipped* with
the date and how it was checked, update §4 if anything was seen on screen, add any decision to §6, and add a
short note to §8. Details at the bottom.

Status: ⬜ not started · 🟡 partly done · ✅ done. Priority: **P0** next · **P1** soon · **P2** nice to have ·
**P3** someday / risky.

---

## 1. Where things stand

VibeCheck is a native macOS (14+) menu bar system monitor: CPU, GPU, memory, network, disk, sensors,
battery, AI agents, clock and weather, summed up by a **vibe score** (vibing / mid / cooked). Clicking the
menu bar item opens the **deck**, a Liquid Glass panel with live tiles that unfold into detail views, a ⌘K
command palette and keep-awake controls. Settings is a sidebar window with a live menu bar preview. Full
feature list: [README](../README.md).

**Product rules** (from three design reviews, §5): verdict first, numbers on demand; one ring beside the
notch, and width or color only when there's bad news; every feature reuses data VibeCheck already collects
before anything new is added; can it be a ⌘K command instead of a button?

**Installed** at `/Applications/VibeCheck.app` (launch at login on), signed with the owner's Apple
Development identity. Owner's setup: separate items, tight spacing, ring on; Memory, Disk and Clock off;
notch cap 0.

**Biggest open gaps:** on-screen checks (§2 items 1–12): animations, light mode, the Settings drags, most of
the 2026-11-19 batch, and the owner-only accessibility and Bluetooth checks. Nobody outside the team can
install it yet (public distribution is P3 by the owner's choice).

---

## 2. Remaining

One list, highest priority first. **QA** = the QA agent can do it while the owner keeps hands off the Mac
(see "On-screen QA" in §7); **Owner** = only the owner can. Fix whatever turns up before starting new features.

| # | Item | Who | Pri | What's left / notes |
|---|---|---|---|---|
| 1 | Deck: light mode, tile press, unfold / fold animation | QA | P0 | Hover outline seen 2026-11-19. Light mode needs a relaunch with `-AppleInterfaceStyle Light`; animations need a screen recording or a human |
| 2 | Ring motion: bounce; wobble on the deck header ring | QA / Owner | P0 | Menu bar wobble seen 2026-11-19; burst captures too coarse for the bounce |
| 3 | Cup inside the ring (ring-only style) | QA | P0 | Ring-only style itself seen 2026-11-19; owner keeps keep-awake as its own item, so switch temporarily and restore |
| 4 | Settings: drag to reorder, number drag, banner preview, "Advanced" sections | QA | P0 | Save and restore `local.vibecheck.app` before reordering. "Advanced" didn't open with AXPress; try a real click before calling it a bug |
| 5 | Quit / Force Quit confirmation dialog; mic-muted and shortcuts-paused chips | QA | P0 | Needs a throwaway process that is the loudest (never confirm on a real app). Red dot and palette commands seen |
| 6 | 2026-11-19 batch not yet seen: ring drop and ⌥-click, notch auto-collapse, toggle shake, update hint, vibe strip, battery history, recovery check, culprit drain, network extras | QA | P0 | Palette process commands seen; call guard / Wi-Fi trigger / public IP rows only in the accessibility tree. Details in §3 |
| 7 | Agent watch: session ends after 3 quiet minutes; "is done" notification | QA | P0 | Trigger start seen with `pmset` |
| 8 | Widgets: small "Vibe", light / tinted modes, update after a vibe change, dim after quitting | QA / Owner | P0 | Medium "CPU and Memory" seen by the owner |
| 9 | Reduce Motion and Increase Contrast: readable, springs become fades | Owner | P0 | System settings; QA doesn't toggle them |
| 10 | Real VoiceOver over the deck, menu bar items, palette; alert number adjustable | Owner | P0 | Tiles read as sentences in the accessibility tree |
| 11 | Bluetooth off while asleep: permission prompt, really off in sleep, back on after wake | Owner | P0 | Switch it on in Settings → General, sleep, wake, check the log (§7) |
| 12 | Agents settings rows seen rendered; switching to a second Claude account (live limits follow) | Owner | P0 | Logos seen 2026-11-19; picker shows one account |
| 13 | Clipboard spike: what macOS 26+/27 pasteboard privacy does to a background reader (`NSPasteboard.accessBehavior`, the "Paste from other apps" prompt) when polling `changeCount` | Dev | P1 | Decides whether history is possible without a prompt on every copy. If it prompts, history becomes "record while the deck is open" or is dropped; snippets still ship |
| 14 | Clipboard history store (`App/ClipboardHistory.swift`): poll `changeCount` every 0.5 s; keep the last 50 text (≤64 KB), image (≤5 MB) and file items with source app and time; dedupe | Dev | P1 | **Off by default.** Never records `org.nspasteboard.ConcealedType` / `TransientType` / `AutoGeneratedType`, anything copied while Secure Input is on, or apps on an ignore list (password managers preset). Memory only unless "keep across restarts" is on |
| 15 | Clipboard in ⌘K: a "Clipboard" section (and a `clip` filter), ↩ puts the item back and pastes into the previous app; ⌘↩ actions: paste as plain text, pin, delete; optional global shortcut opens the palette in clipboard mode | Dev | P1 | Auto-paste posts ⌘V, which needs Accessibility; without it ↩ only copies and says "Copied, press ⌘V". Ask for Accessibility only on first use |
| 16 | Pinned snippets: pin from history or add in Settings; shown first in the Clipboard section; stored on disk and included in settings backup (add the key to `SettingsBackup`) | Dev | P1 | Snippets are typed or pinned on purpose, so they persist even with history off |
| 17 | Settings → Clipboard page: on/off, history length, keep across restarts, ignored apps, clear history, manage snippets; ⌘K "Clear clipboard history" | Dev | P1 | Run `vibecheck-reviewer` on C1–C4 (reads possibly sensitive data) |
| 18 | Find my cursor: ⌘K command and optional shortcut; a click-through ring flashes around the pointer (0.8 s, a fade with Reduce Motion) | Dev | P2 | No permissions. One borderless panel on the pointer's screen |
| 19 | Keyboard cleaning mode: ⌘K "Clean keyboard" swallows key, modifier and media-key events for 45 s with a countdown overlay; click "Done" on the overlay to end early | Dev | P2 | `CGEventTap`, needs Accessibility (asked on first use). Can't block Touch ID / power key; say so on the overlay. Run `vibecheck-reviewer` (acts on input) |
| — | Mouse and keyboard batteries and low-battery alerts | — | — | Already shipped (`DeviceBatteryMonitor`, accessory battery alert); no new work |
| 20 | App Shortcut phrases out of code into `AppShortcuts.xcstrings` | Dev | P2 | Needs `build.sh` support and a check with a built app |
| 21 | Translations | Dev | P2 | None yet |
| 22 | Private-API recheck after each macOS update: `IOHIDEventSystemClient*`, `responsibility_get_pid_responsible_for_pid`, SMC `PSTR`/`PDTR`/`F0Ac`, `IOBluetoothPreference{Get,Set}ControllerPowerState` | Dev | Tech debt | Last checked 2026-11-19 on macOS 27.2.1 (26B131), M5: all working (`--dump` + a `dlsym` probe) |
| 23 | Public distribution: paid Apple Developer Program, "Developer ID Application" cert (same team `77HKFF78Z8`, app group), `notarytool` profile, first real `scripts/release.sh`; on the notarized build check Wi-Fi trigger, Bluetooth snooze, Apple Events and the widget; publish `v<version>` (repo must be public); Gatekeeper on a second Mac; Homebrew cask last | Owner | P3 | Sharing with colleagues already works (`scripts/release.sh --share`). Apple Development cert expires Nov 2027 |
| 24 | Website / landing page from the brand assets | Dev | P3 | Owner skipped it 2026-11-19 |
| 25 | GitHub social preview: upload `branding/png/social-card.png` | Owner | P3 | Only possible once the repo is public |

**Not planned:** another app's window, Dock, file, screenshot, recording,
uninstaller, lyrics and companion tools, its "Dynamic Island" bar, and API cost estimates. Not planned either: a mouse jiggler, scroll direction per device, typing stats and key remapping (input
monitoring). Also dropped by the
owner (2026-11-19): fan control, disk cleaner, calendar in the Clock panel, keep awake with the lid closed, a
sandboxed App Store edition, display brightness, iCloud settings sync, and the dark mode quick toggle.

---

## 3. Shipped

Newest first. Versions 1.0–1.5 (the ten monitors, deck, Settings, alerts, history, notch fit, Shortcuts
actions, keep awake, notification history) are in `git log` and the README.

| Date | Feature | How it was checked |
|---|---|---|
| 2026-11-19 | **Private APIs re-checked on macOS 27.2.1**; `--dump` APPS line names apps like the deck does (it showed helper names when the parent had no traffic) | `--dump` + a `dlsym` probe on live Chrome helpers |
| 2026-11-19 | **Wider pop-ups**: deck 360→390 pt (tiles 114 pt), notifications 320→346, ⌘↩ actions card 250→270, settings alerts widened to 288 | Tests; installed and approved on screen by the owner |
| 2026-11-19 | **P0 QA pass, verified**: ring symbol in all three states at 16 pt with the replace transition and the deck header ring; ring badge ("CPU 91%") and verdict tooltip | Seen on the installed app with `scripts/qa` captures under a `yes` load; owner defaults diffed identical afterwards |
| 2026-11-19 | **Fixes from the QA pass**: Agents card "Working now" no longer wraps; `build.sh` rebuilds when a no-op release build leaves the App Intents const values empty (the install failed with "App Intents metadata missing") | Tests; two `./build.sh` runs in a row both succeed; badge seen on one line by the owner on the installed build |
| 2026-11-19 | **Mood wobble on the ring** (option C from the design canvas, few nodes): still while vibing; mid shows three bumps and cooked four, drawn by `RingWobble` through `WobbleRingView` (shape layers, precomputed frames swapped by a 20 fps timer; Reduce Motion keeps the plain ring) | Shapes seen in the menu bar under load (yellow 3 bumps, red 4 bumps); CPU under the same load 2.7% vs 2.2% without the wobble (a SwiftUI TimelineView version cost ~30%). **Motion not seen:** timed captures 0.28 s apart showed the same frame; left unresolved at the owner's request |
| 2026-11-19 | **Ring as a custom SF Symbol:** `vibe.ring.vibing / .mid / .cooked` (full, two-thirds, one-third), two layers (track secondary, arc primary) drawn in palette mode, three weights so it follows the type weight (regular in the menu bar, light in the deck). Written by `scripts/render_ring_symbol.swift` into `Resources/Symbols.xcassets`, compiled by `build.sh` with the icon into `Assets.car`; state changes use a symbol replace. Drawn shapes stay as the fallback when `Assets.car` is missing (`swift test` / `swift run`). Variable value was not used: its SVG annotation isn't documented anywhere reachable without the SF Symbols app | Symbols compiled by actool and listed by `assetutil`; rendered offscreen from the built app's catalog at 16 / 36 / 64 pt in three weights beside the old drawn ring (same thickness); 3 unit tests; not seen in the menu bar. Redraw cost not measured |
| 2026-11-19 | **Removed:** the Dark (dark / light mode) quick toggle, from the deck and ⌘K; System Events is no longer used (Finder only, for Empty Trash) | 237 tests passed after the removal; not seen on screen |
| 2026-11-19 | **Branded DMG install window:** night-sky art from `scripts/render_dmg.swift` (`branding/dmg/`), step 1 "drag into Applications" with a gradient arc arrow, step 2 the Terminal line in a code chip next to "How to open.txt"; 100 pt icons, label plates readable in black or white, VibeCheck volume icon. The notarized release uses a variant without step 2. `release.sh` lays it out through Finder and checks the finished DMG's `.DS_Store` | Finished `--share` DMG opened fresh in Finder and screenshotted: art, icons, labels and volume icon all right. Release variant rendered, not built (no Developer ID). Needs Terminal to be allowed to control Finder (asked once) |
| 2026-11-19 | **Distribution pipeline (code side):** `scripts/release.sh` builds with a Developer ID (hardened runtime + timestamp via `build.sh`), notarizes and staples the app, makes `build/release/VibeCheck-<version>.dmg` (app + Applications link), signs, notarizes and staples the DMG, runs `spctl`, writes a SHA-256; `--share` (alias `--dry-run`) skips Developer ID / notarization and adds a "How to open" note to the DMG, for colleagues. Apple Events and Location entitlements added for the hardened runtime. **Update check** against the latest GitHub release (About page toggle, default on, at most daily; Check Now; one notification per new version; ⌘K "Check for Updates") | `release.sh --dry-run` (Apple Development + hardened runtime): signature verifies, DMG mounts with the app and an Applications link, the app inside verifies, `--dump` runs under the hardened runtime. Real Developer ID signing, notarization and Gatekeeper not run (no certificate yet). Update check: 14 new unit tests (237 total; only https GitHub links are opened), no real network call, not seen on screen. Reviewed; fixes applied |
| 2026-11-19 | **Desktop widgets** (macOS 14+): small "Vibe" (ring, vibe word, reason or CPU / memory) and medium "CPU and Memory" (ring, verdict, last-hour sparklines). The app writes a snapshot into the app group `77HKFF78Z8.local.vibecheck` once a minute while a widget is placed and reloads timelines on a vibe change (≥5 min apart, a throttled one goes out later); widgets re-read every 15 min and dim on time once the snapshot is 15 min old. Built by SwiftPM as an `-application-extension` executable and wrapped into `PlugIns/VibeCheckWidget.appex` by `build.sh` (no Xcode project); only with the Apple Development identity | Unit tests (downsampling, file round trip, staleness, snapshot); build signs the appex (sandbox + group) and the app (group); signed app launches; `pluginkit` lists `local.vibecheck.app.widget` after `lsregister`. Owner saw the medium widget on the desktop with live data (vibing); small widget, light / tinted and updates not seen. First build crashed at launch: the extension must be linked with `-e _NSExtensionMain` |
| 2026-11-19 | **Tech debt cleared:** `Panels.swift` split per module (`CPUGPUPanels`, `MemoryPanel`, `NetworkPanel`, `DiskPanel`, `SensorsPanel`, `BatteryPanel`, `ProcessList`); `--deck-demo` moved to `AppDelegate+DeckDemo.swift` (still in release builds, which QA runs); clock formatter cache behind a lock; `AppSettings` grouped into `settings.menuBar` / `.clock` / `.weather` / `.keepAwake` with unchanged defaults keys | Pure refactor: build clean, 223 tests pass, defaults key sets diffed old vs new (identical), reviewed; not run on screen |
| 2026-11-19 | **Brand mark redrawn as the Mood Dial:** `mark-on-light/-dark/-mono.svg` are now the ring, a solid knob with a notch cut toward the gap, and the check in the gap (SVG masks, which AppKit's renderer handles); mark PNGs and both lockups re-rendered; BRAND.md §2 and the README updated | Mark (light, dark, mono) and both lockups rendered and looked at |
| 2026-11-19 | **New app icon, "Mood Dial":** the chosen AI render (`branding/art/icon-render.png`) is the icon itself: `render_brand.swift` cuts out its plate, fills its rounder corners with nearby plate color and masks it to the squircle for `AppIcon.icns`, and writes the same plate as the single layer of `VibeCheck.icon`; `icon-small.svg` redrawn for 16/32 px; the vector `icon.svg` and the glass SVG layers removed. Mark and wordmark unchanged | Rendered PNGs and corners looked at; `actool` compiled the `.icon`; the built app's icon drawn through `NSWorkspace` and looked at (macOS 26 shows the render). Not seen in the Dock / Finder, or in tinted and clear modes |
| 2026-11-19 | **Liquid Glass app icon:** `branding/VibeCheck.icon` (Dusk→Night fill, glass group with the ring and the pulse / check), compiled by `actool` in `build.sh` into `Assets.car` (`CFBundleIconName`); `AppIcon.icns` stays for macOS 14–15 | actool compiles it; `assetutil` lists it; the app's icon rendered through `NSWorkspace` and looked at. Dock / Finder in light, dark and tinted not seen |
| 2026-11-19 | **String Catalog finished:** Shortcuts actions (titles, parameters, dialogs, stat sentences), Focus filter, accessibility labels and the remaining tooltips; new text goes through `Text("…")` / `String(localized:)` + `scripts/extract_strings.sh`. Integers that can pass 999 go in as `String(n)` | Tests compare English output with the old strings; not seen on screen |
| 2026-11-19 | **Fix:** opening Settings crashed (the menu bar preview drew the ring label, which required the drop state only the real item has) | Crash reports read; regression test hosting the labels with Settings' environment; fixed build installed |
| 2026-11-19 | **Ring-first menu bar:** new menu bar style "Just the vibe ring", the default for new installs (existing installs keep their style); the ring badge names the culprit in that style. **Cup in the ring** while keep awake runs, unless "Show keep awake as its own item" is on (existing setting, relabelled; the owner's stays on) | Unit tests with a throwaway defaults suite; cup size inside the 16 pt ring and the ring-only item not seen |
| 2026-11-19 | **Focus filter** for the call guard: per Focus, "Hold alerts" and "Keep display awake" (System Settings → Focus → Add Filter → VibeCheck); state kept across relaunches | Unit tests for the rules; not tried in a real Focus, and the filter's presence in the intent metadata not checked |
| 2026-11-19 | **Agent switches apply everywhere:** agents switched off on Settings → Agents are left out of the deck (cards, totals, charts, Now list) and agent watch, not only the menu bar item | Unit test with a fixture log; installed, not seen |
| 2026-11-19 | **String Catalog** (English only): 691 strings, `build.sh` copies `en.lproj` into the app | Tests compare English output; not seen on screen |
| 2026-11-19 | **Ring:** ⌥-click toggles keep awake; drop a file / folder (awake until it stops changing, 10 s quiet) or an app (awake while it runs), ring dilates 1.1× while hovered; **notch auto-collapse** to the combined item after a separate item is hidden 8 s, one-time notice, switching back opts out for good | Unit tests (`NotchFit.isHidden`, debounce, drop kinds); not seen on screen (no drag tried, no notched-display check) |
| 2026-11-19 | **Deck and palette:** Empty Trash is a ⌘K command only (second ↩); palette remembers the last 8 commands; "Quit / Force Quit <app>" for the top 3 apps by CPU and "Turn on/off alert: …"; failed toggles shake (fade under Reduce Motion) with symbol replace; cup tooltip names the hold dial; one dismissible tip line after an update | Unit tests (ranking, commands, hint versioning); not seen on screen |
| 2026-11-19 | **New-install defaults:** six tiles (CPU, Memory, Network, Sensors, Battery, Agents); Clock, Weather, GPU, Disk off; existing settings untouched. **Settings "Advanced"** sections (General: update rate, Bluetooth; Menu Bar: spacing, colorful graphs, notch; Shortcuts; Alerts: restore / test; module pages: shortcut) | Unit tests with a throwaway defaults suite; Advanced sections not seen |
| 2026-11-19 | **Vibe replay:** 30-day log of mid / cooked episodes, 24 h vibe strip and "X cooked your Mac N times this week" at the top of the CPU view. **Battery history:** 90-day charge chart and max-capacity trend | Unit tests with temp files; not seen |
| 2026-11-19 | **Call guard** (on by default): camera / mic in use holds non-critical alerts until the call ends (temperature and battery still come through), keeps the display awake, warns once per call about an app at ≥100% CPU with a Quit button (graceful, `ProcessKiller`). **Keep awake while on Wi-Fi X** (asks for Location only when switched on) | Unit tests; real device detection, notification action and Location prompt not tried |
| 2026-11-19 | **Network extras:** opt-in public IP (api.ipify.org, every 10 min, privacy note), Wi-Fi details (SSID, RSSI / noise, channel, PHY, rate), top apps over the last hour | Unit tests, no network; not seen |
| 2026-11-19 | **Recovery check** through the ring's gap on cooked / mid → vibing (never on launch; 150 ms fade under Reduce Motion) and **culprit drain** after quitting the culprit from the deck | Unit test for the transition rule; animation not seen |
| 2026-11-19 | **Agent logos and Claude accounts:** each agent's own logo instead of ✨ (menu bar item, agent cards, Now list); Agents settings lists every agent with its logo, found / not found, and a switch for the menu bar item; **Claude account** picker reads one Claude Code profile (default, auto-found `~/.claude-*` folders, or "Choose account folder…"), and live limits run Claude Code as that account | Unit tests (parser, logo choice, profile discovery, scanner per profile); logos and the settings page rendered offscreen and looked at; not seen on screen |
| 2026-11-19 | **Settings reorganized** like System Settings: searchable sidebar in groups (app pages · Monitors · Extras) with colored icon tiles; one page per module (on/off, menu bar look and options, that module's alerts, shortcut); About page; Claude live limits moved to Agents | Unit tests; detail pages rendered offscreen and looked at; sidebar and search not yet seen on screen |
| 2026-11-19 | Agents detail: shorter and limits-first (agent cards on top, compact one-line gauges, 24 h and 7-day charts side by side, top 3 projects) | Tests; seen on screen (deck 928 pt tall, was over 1032 and clipped). `qa`: restored `pos`, which the input guard needs |
| 2026-11-18 | Cleanup: unused QA helpers removed, `qa item` matches by prefix | Tests; `qa item` against the installed app |
| 2026-11-18 | **Agent watch:** keep awake while an AI agent is working (log write in the last 3 min); opt-in "<Agent> is done" after runs of 10+ min | `pmset -g assertions` with the trigger on / off; unit tests |
| 2026-11-18 | **Ring badge:** "CPU 96%" beside the ring on mid / cooked, unless the culprit has its own item | Unit tests; installed, not seen |
| 2026-11-18 | **Verdict tooltip** and VoiceOver label on the ring and combined items | Unit tests; label seen in the accessibility tree |
| 2026-11-18 | Keep-awake **hold dial** on the deck's cup (15m / 1h / 4h / ∞) | Seen with a synthetic drag |
| 2026-11-18 | Pinned detail header | Seen (Sensors) |
| 2026-11-18 | Deck round two: search field, live chips, footer, 104 pt tiles, culprit outline, ⌘↩ actions | Seen in dark mode |
| 2026-11-18 | ⌘K palette, type-to-act, tile hover chevron, glass hairline on macOS 14–15 | Palette typing seen; hover not |
| 2026-11-18 | Keep awake **on a schedule** and **while files are downloading** | `pmset -g assertions` |
| 2026-11-18 | Quick toggles: Dark, Mic, Empty Trash | Never run for real (Automation prompt) |
| 2026-11-18 | Focus sessions in the cup menu | Unit tests |
| 2026-11-18 | Connected USB devices; accessory battery alert | Unit tests; no device plugged in |
| 2026-11-18 | Separate-items reorder from Settings | Unit tests |
| 2026-11-18 | Listening ports (Network view) | Seen; quitting from it not tried |
| 2026-11-18 | Agents: limit gauges, live Claude limits (via the user's `claude` CLI), Copilot CLI and OpenCode, working-now badge, tokens-per-hour alert, 7-day chart | Seen in the QA pass + `--dump` |
| 2026-11-18 | Secure input warning (Settings) and "Shortcuts paused" deck line | Probe test; not seen |
| 2026-11-18 | Quit / Force Quit, including the process tree | Unit tests with throwaway processes |

---

## 4. Verified vs. not verified

Capture single VibeCheck windows with `screencapture -l <windowID>` (helpers in `scripts/qa`), never the
whole screen.

| Area | Status |
|---|---|
| Data collectors (CPU, GPU, memory, network, disk, sensors, battery, devices, weather) | ✅ real values checked with `--dump` |
| Deck window size and position (open, unfold, fold, close; multi-display; notch geometry) | ✅ frames logged with `--deck-demo` |
| Alerts, history, charts resampling, vibe score, notch fit, settings backup, layout widths | ✅ unit tests |
| Login item registration | ✅ `--login-item status` reports enabled |
| Deck look (dark mode), tiles, sparklines, keyboard focus ring | ✅ seen in the QA pass |
| ⌘K palette rows, key caps, header search, dark + light | 🟡 offscreen renders; ↑↓/↩ and hover chevron not seen live |
| Deck shell round two, live: header, search field, footer, palette typing / ⌘↩ card / esc ×3, keep-awake chip with hover ×, cup menu, hold dial (synthetic drag), pinned header, culprit outline | ✅ seen in dark mode |
| Deck in light mode | ✅ owner looked and it's fine (captures read grey) |
| Mic-muted and shortcuts-paused chips, 1× hairline | ❌ not seen |
| Ring mid (yellow) and cooked (red), "Cooked" verdict in the deck | ✅ seen (7 then 10 busy `yes` loops) |
| Tile hover / press, unfold animation, ring bounce | 🟡 hover outline seen (2026-11-19); press, unfold, bounce ❌ |
| Chart scrubbing bubble | ✅ seen with synthetic mouse moves |
| Range morph, peak haptic, drag-to-adjust numbers | ❌ never touched |
| Deck keys: Esc, arrows, ⌘2 | ✅ synthetic key events |
| Global shortcuts ⌃⌥⌘1–9 from another app | ✅ ⌃⌥⌘2 opened GPU; others not tried |
| Notifications appearing | ✅ test banner seen by the owner; permission prompt not seen |
| Notch auto-fit on the built-in display | ⚠️ maths verified with real widths, not seen |
| Settings: all 8 panes, live preview | ✅ seen (before the 2026-11-19 sidebar regroup) |
| Settings: grouped sidebar, search, per-module pages | ⚠️ detail pages rendered offscreen; sidebar not seen |
| Settings: drag to reorder, number drag, token menus, banner preview | ❌ not touched |
| Launch at login across a real restart | ⚠️ registered, not rebooted |
| Keep awake: assertion held (display / system type) and released | ✅ `pmset -g assertions` + a unit test reading `IOPMCopyAssertionsByProcess` |
| Keep awake: deck cup menu, menu bar cup, Settings pane, status strip | ✅ seen ("Until" submenu not opened) |
| Keep awake triggers: plugged in, external display, downloading, schedule | ✅ built app with launch arguments + `pmset -g assertions` |
| Keep awake "while an AI agent is working": assertion ~3 s after launch while Claude Code wrote logs; none with it off | ✅ built app with launch arguments + `pmset` (2026-11-18). Ending and the "is done" notification: unit tests only |
| Keep awake: ending on unplug / display removal, end notification, ⌃⌥⌘A, "Until" menu | ❌ unit tests only |
| Ring badge beside the menu bar ring; verdict tooltip on hover | ✅ seen 2026-11-19 in ring-only style ("CPU 91%"); none in separate-items style, by design |
| Ring symbol (vibing / mid / cooked), replace transition, deck header ring; wobble motion in the menu bar | ✅ seen 2026-11-19 (timed captures); deck header motion ❌ |
| App Intents metadata in the bundle | ✅ `extract.actionsdata` inspected |
| Shortcuts app lists the 5 actions | ✅ seen by the owner; running them, Spotlight and Siri not tried |
| Idle CPU / memory with the deck closed: ~3.3% / ~100 MB | ✅ installed app, 3× 40 s with `ps` |
| Detail views: CPU, GPU, Battery, Network (+ ports), Sensors, Agents | ✅ seen; Weather not (module off) |
| Swift 6 language mode: no warnings, no runtime isolation crashes in an 80 s run | ✅ |
| Notification history: logic; bell and empty popover | ✅ unit tests; seen. Red dot ✅ (2026-11-19); filled list ❌ |
| Agents: token totals from real logs, menu bar item, tile, cards, gauges, plan badges, Now card | ✅ `--dump` + seen |
| Live Claude limits from the real CLI | ✅ probe test + real menu bar values |
| Copilot CLI / OpenCode parsing and quota | ✅ unit tests + `--dump` |
| 7-day chart, limits gauges with sample data | 🟡 offscreen renders |
| Per-item options: logic and migration; panel | ✅ unit tests; panel rendered offscreen, not seen expanded |
| Bluetooth off while asleep: private calls, permission read, `--dump` line | ✅; prompt, toggle and real sleep ❌ |
| Quit / Force Quit: rules and real child process | ✅ unit tests; menus and confirmation ❌ |
| Secure input detection | ✅ probe test; warning and deck line ❌ |
| Listening ports: `lsof -F` parsing; section in the deck | ✅ 7 unit tests; seen (quit not tried) |
| P2 batch (2026-11-19): ring drop / ⌥-click / notch auto-collapse, palette process commands, toggle shake, update hint, Advanced sections, vibe strip, battery history, call guard, Wi-Fi trigger, network extras, recovery check, culprit drain | 🟡 palette process commands seen; settings rows in the accessibility tree; the rest ❌ |

---

## 5. Design rules

Condensed from three reviews: the "menu bar Creative Director" brief (round one), a popover
mockup (a different app, round two; the HTML file was removed 2026-11-19, it is in git history) and the Apple Design Award style
teardown (round three). BRAND.md still decides voice, color and motion.

**The idea.** A verdict first and a cockpit second, in a 390 pt sheet of glass. Everything folds behind three
doors: **tile → detail**, **cup → menu**, **⌘K → anything**. Before adding UI, ask whether it can be a palette
command.

**What the ADA teardown said (round three).** Award-grade: the verdict-first idea, the single non-activating
deck, the drawn ⌘K field, the culprit outline. Holding it back: too many jobs at once (Empty Trash, Clock
and Weather fail the menu bar test), separate items a notched MacBook will evict, idle cost that scales with
item count, hidden gestures, unverified accessibility, no distribution. The §2 items marked P1/P2 under
"Menu bar and deck", call guard and vibe replay come from it. Full text: in git history (removed from this file 2026-11-19).

**Menu bar**
- Monochrome by default; color only when the vibe isn't vibing. Width is earned the same way: the ring
  grows a badge only on mid / cooked, and not when the culprit has its own item.
- A status item's length is never re-measured by macOS: set it explicitly whenever content changes shape.
- Haptics only fire with a finger on a Force Touch trackpad: use them for direct manipulation (dial
  detents, chart peaks), never for background events.

**The deck shell, top to bottom** (390 pt wide since 2026-11-19, never wider)

| Zone | Height | Rule |
|---|---|---|
| Header | ~50 pt | Ring + verdict title, then only bell and cup |
| Search field | 28 pt | Always visible, drawn (the panel never takes focus); ⌘K key cap; click it or just type |
| Live chips | 0 or 26 pt | One pill per thing happening now (keep awake / focus, mic muted, shortcuts paused); hover shows × to stop; absent when nothing is live |
| Body | flexible | Quick toggles (one row, max three) + bento grid, or palette results |
| Footer | 30 pt | Settings (⌘,) · version · Quit; key hints and result count while the palette is open |
| Detail view | up to the screen | Matched-geometry unfold; pinned header; lists cap at 8 rows + "+N more" |

- Tiles: 3 columns, 8 pt gutters, (390 − 32 − 16) / 3 = **114 pt** so edges land on whole pixels. One hero
  number per tile; detail lives one click deeper.
- Settings stays a separate window; the deck never shows a configuration control except the quick toggles.

**Materials**
- macOS 26+: `NSGlassEffectView`, 18 pt continuous corners. Glass appears once; tiles, chips and rows use
  `.quaternary` fills at 55% (90% on hover).
- macOS 14–15: `NSVisualEffectView` `.popover` / `.behindWindow` plus a 0.5 pt inner hairline (white 10% dark,
  black 8% light); at 1× it's 1 px at half opacity.

**Type** (SF Pro only)

| Role | Spec |
|---|---|
| Verdict title | 15 pt semibold, SF Pro Text |
| Tile hero number | 17 pt semibold SF Pro Rounded, `monospacedDigit()`, tracking −0.2, `numericText` transition |
| Tile title, palette row | 11 / 13 pt medium, `.secondary` / `.primary` |
| Section labels | 11 pt semibold, sentence case |
| Key caps | 10–11 pt medium SF Pro Rounded, `.tertiary`, 4 pt capsule at `.quaternary` |
| Minimum | 10 pt anywhere |

**Color.** Module accents are system-adaptive and appear on the tile's icon and sparkline only. State color
is earned: mint / yellow / red for vibing / mid / cooked, orange for "paused" facts. Selected palette row:
`Color.accentColor` at 14%.

**Micro-interactions (shipped)**
1. Tile hover: fill 55% → 90%, 10 pt chevron fades in top-right (150 ms ease-out in, 120 ms out).
2. Palette selection: 14% accent fill moves to the row, a `return` key cap replaces its shortcut (120 ms).
3. Press: 97% scale, spring 0.2 / 0.7.
4. Culprit tile: 1 pt inner stroke in the state color at 40% (240 ms in, 400 ms out); the hero number turns
   red only when cooked (yellow text is unreadable on light glass).
5. Live chip stop: 18 pt × fades in on hover (150 ms).
6. ⌘↩ on a palette row: Run plus the matching Settings pane.
7. Hold dial: hold the cup 350 ms, drag up / right / down / left for 15m / 1h / 4h / ∞; release in the 12 pt
   dead zone cancels.

Unchanged from BRAND.md: deck open (anchored drop, 0.38 s) and tile → detail unfold (spring 0.38 / 0.86,
25 ms stagger).

**Benchmarks.** launcher apps for the command bar (type anywhere, keyboard selection with the mouse still
working, shortcut hints on the right). dense menu bar monitors for density (one number per tile, axis-less sparklines).
From another app, left out on purpose: four-column toggle tiles, blue accent fills on active tiles, grouped
results while typing, its 12 pt radius and web fonts.

---

## 6. Decisions log

Choices future sessions shouldn't silently undo.

| Decision | Why |
|---|---|
| Mouse, keyboard and clipboard back on the roadmap (2026-11-19, owner): clipboard history in ⌘K and pinned snippets (P1); find my cursor and keyboard cleaning mode (P2). History is off by default and never records concealed / transient items or anything copied during Secure Input | Owner asked for them. Kept to ⌘K commands and the fewest permissions, per the product rules; no input monitoring |
| Deck 390 pt (was 360), notifications popover 346 pt, ⌘↩ actions card 270 pt, alerts widened to 288 pt with an empty accessory view (2026-11-19) | Owner asked for wider pop-ups (~20% was too much; settled ~8% over the old sizes). 390 keeps tiles whole-pixel (114 pt) |
| Share with colleagues through an un-notarized `--share` DMG signed with Apple Development, not a paid Developer ID | The owner wants to share, not sell; each person runs one `xattr -dr com.apple.quarantine` command (a colleague found Open Anyway didn't work on their Mac, 2026-11-19; Terminal did). Building from source would need Xcode and repo access and loses the widget (team-signed app group) |
| Updates via the GitHub Releases API (`releases/latest`, tag `v<version>`, first `.dmg` asset), not Sparkle; the app opens the download, it doesn't replace itself | No framework to embed with SwiftPM, no EdDSA keys; enough for a small app. Revisit Sparkle if silent in-place updates are wanted |
| Hardened runtime only for Developer ID builds (or `VIBECHECK_HARDENED=1`), not the owner's daily Apple Development builds | Notarization needs it; keeps local builds as they were |
| The flat brand mark is the Mood Dial (ring, notched knob, check in the gap), not the old pulse-to-check | The owner asked for the mark to follow the app icon so the lockup, README and icon tell one story |
| Widgets without an Xcode project: SwiftPM builds the extension executable (linked with `-e _NSExtensionMain`), `build.sh` wraps and signs the `.appex` | Keeps the "no Xcode project" decision; without that entry point the extension traps on load |
| Team-prefixed app group (`77HKFF78Z8.local.vibecheck`), main app stays unsandboxed | Works without a provisioning profile; only the widget is sandboxed, as WidgetKit requires |
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
| Brand assets generated from SVG by `scripts/render_brand.swift`; the app icon alone comes from a 3D render (`branding/art`) | One source of truth; `NSImage` renders SVG natively. The owner chose the render's look over a vector redraw, which couldn't match its materials |
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
| Two Claude Code accounts = two profile folders (`CLAUDE_CONFIG_DIR`); VibeCheck reads **one** chosen profile, per Mac, not in settings exports | Matches how Claude Code separates accounts; one account at a time keeps the menu bar number, limits and cards unambiguous. Live limits pass `CLAUDE_CONFIG_DIR` to the CLI |
| Agent logos are Simple Icons paths (CC0) drawn by a small SVG path parser (`Views/AgentLogo.swift`); OpenCode's square O drawn from its favicon | No image assets or new dependency; shapes take the menu bar tint like SF Symbols. The menu bar logo is the agent the number comes from (limits) or the busiest counted agent |
| `SIGPIPE` is ignored app-wide | Child processes (`ps`, `lsof`, `nettop`, `claude`) can exit before we write to them |
| Alerts and the vibe score don't depend on which modules are shown (owner, 2026-11-18) | A CPU alert should fire even with the CPU item hidden; so CPU, memory, disk, sensors and battery are always sampled. Only samples nothing else needs (accessory batteries) are gated |
| Keep Awake item: click toggles with the default length, right-click/⌃/⌥-click opens the menu (owner, 2026-11-18) | The owner wanted the default set in Settings and started by a click; the menu keeps the other options one click away |
| Quick toggles act through Finder / CoreAudio only (dark mode removed 2026-11-19); Trash is emptied by Finder, never by deleting files | The user's own undo and Finder's rules apply; Automation permission is asked on first use (`NSAppleEventsUsageDescription`) |
| ⌘K palette draws its query instead of using a TextField; keys come from the deck's key monitor | The deck is a non-activating panel that never takes focus from the user's app; a real field would need it to |
| Palette never offers Empty Trash or process kills; Quit needs a second ↩ | Type-to-act means "q" + Return would quit; Return in a list is too easy to hit by accident |
| A finished focus session always notifies | It's the point of a focus timer; other keep-awake endings follow the notify setting |
| Separate items' autosave names carry a generation (`vibecheck.cpu.g3`) bumped on each Settings reorder; generation 0 keeps the original names | macOS 27 remembers item positions by autosave name outside the app's defaults; new names are placed in creation order, each to the left (probe app). Don't revert to fixed names |
| Limit lists key on `RateWindow.key` (length + name) | Copilot's two monthly quotas share a length; keying on length drew one twice |
| Agents module: no network of its own; live Claude limits run the local `claude` CLI | Keeps "local logs only" true for VibeCheck itself |
| No cost estimates in the Agents module (owner, 2026-11-18) | It would need downloading a price list; never hard-code prices either |
| Settings: one sidebar page per module; the Menu Bar page keeps only order, on/off and display, and › opens the module page. Monitors list in fixed order, not the menu bar order | Options live in one place; a sidebar that reshuffles on reorder is hard to scan |
| Settings footers use `settingsFooter()` (caption, leading) | Grouped `Form` footers align trailing by default on macOS |
| Chart areas add points with `addLine`, never `addLines` | `addLines` starts a new subpath and breaks the closed fill |
| Agent watch counts an agent as working for 3 min after its last write (not the 2 min "working now" rule) | Long tool calls (tests, builds) write nothing for minutes; a shorter gap would end the session and notify mid-run |
| Agent logs are scanned while the Agents module, the agent keep-awake trigger or the "is done" notification is on | The features work with the Agents item hidden; still local files only |
| The ring's badge is skipped when the culprit's module has its own item; the ring re-measures only when the badge's shape (digit count) changes | Says nothing twice; neighbours don't shift as values change |
| Ring and combined items' accessibility labels end with the verdict (`qa item` matches by prefix) | VoiceOver and hover give the answer without opening the deck |

---

## 7. Working on the project

```bash
./build.sh                       # build/VibeCheck.app
./build.sh --install             # also replaces /Applications/VibeCheck.app (relaunch the app afterwards)
swift test                       # all tests
.build/debug/VibeCheck --dump    # one sample from every monitor (after swift build)
build/VibeCheck.app/Contents/MacOS/VibeCheck --deck-demo   # logs deck/settings window frames + notch fit
/Applications/VibeCheck.app/Contents/MacOS/VibeCheck --login-item status
swift scripts/render_brand.swift # regenerate icon and brand assets from branding/svg and branding/art
scripts/qa/build.sh && .build/qa/qa help   # on-screen QA tools
```

- Settings live in the `local.vibecheck.app` defaults domain; history in
  `~/Library/Application Support/VibeCheck/history.json`.
- Work on `main`; conventional commit messages; **no Claude attribution** in commits or PRs.
- Repo: `saroj-shahi/vibecheck` (private).
- When changing settings on the owner's Mac for testing, **save and restore their exact values** (a past
  session briefly dropped their Clock and Battery items by restoring an outdated list).

### Lessons and testing tips

- **Launch arguments override settings without touching them**: `-keepAwakeAtLaunch YES`; values read with
  `as? Bool` / `as? Int` need plist syntax (`'<false/>'`, `'<integer>540</integer>'`), or the default is
  used. In zsh put them on the command line; unquoted `$args` and `set -- $var` don't split words (use `${=var}`).
- **Measuring CPU**: compare builds one at a time, never side by side (a hidden second item skips the SwiftUI
  drawing that dominates the cost). Use `ps` over 40 s and `sample` for where time goes.
- **On-screen QA**: owner hands-off; drive buttons with `AXPress` / `AXSelected` (no focus needed). Window
  captures show covered windows, but clicks land on whatever is on top. A cursor-moved guard (`PAUSE`) means
  the owner is using the Mac: stop. Synthetic clicks don't open submenus; synthetic drags need a CGEvent
  script (`qa` has no drag command). Before sending a key, confirm the deck is on screen (layer 101). The deck
  closes whenever another app activates, and a full-screen app hides that display's menu bar.
- **Offscreen renders**: use AppKit (`NSHostingView.cacheDisplay`) for real controls; `ImageRenderer` skips
  pickers and toggles.
- **Forcing vibe states**: 7 of 10 cores busy (`yes > /dev/null`) gives mid after ~45 s, 10 gives cooked. The
  verdict then names "claude" as loudest when the load is spawned from Claude Code (app grouping, not a bug).
- **Menu bar**: the notched built-in display shows fewer items than the external one, so accessibility
  listings vary with the active display. macOS 27 keeps item positions outside the app's defaults (see the
  autosave-generation decision).
- **Signing**: the Keychain "Always Allow" only survives rebuilds with a Team ID (`teamid:` in the partition
  list). The Apple Development cert needed Apple's WWDR G3 intermediate installed.
- **Swift 6**: runtime isolation checks may still fire in paths not yet exercised (notification permission
  callback, Bluetooth device fetch); watch for crash reports.
- **SF Symbols**: check a symbol exists with `NSImage(systemSymbolName:)` before using it
  (`keyboard.badge.exclamationmark` doesn't exist on this macOS).
- **Secure input**: Carbon hot keys get no event at all while it's on, so the deck shows a standing line
  instead of reacting to a blocked press.
- **Downloads trigger**: a project hook blocks Bash commands that look destructive (deletes, even in quoted
  text); finish a fake download by renaming it.
- **Bluetooth sleep**: check with
  `log show --last 10m --predicate 'process == "VibeCheck" AND eventMessage CONTAINS "Bluetooth"'`
  (expect "Bluetooth off for sleep" / "Bluetooth back on (wake)"). While asleep a Bluetooth keyboard or mouse
  can't wake the Mac and Apple Watch unlock won't work.
- **Agents**: first scan of a week of Claude logs (~1.1 GB) takes ~1 s, rescans ~30 ms. Tests must pass empty
  locations, or they read the real home folder. "VibeCheck 2" briefly at 50% CPU is the Claude limits check
  (a child process), not a bug.
- **Rejected**: rendering the status label to an image (worse CPU), slowing the refresh to save idle CPU (no
  change; the cost is AppKit redrawing each item per display), reading the Claude token through
  `/usr/bin/security` (an "Always Allow" would cover every process that runs it).

### Known limits (by design or by macOS)

- Idle cost is mostly macOS: ~3.3–3.8% CPU, ~100 MB, almost all in `NSStatusItem _updateReplicants`
  (~30 ms per display per redraw). Fewer items is the lever (P1 ring-first).
- Battery temperature isn't exposed on the owner's Mac (row hides itself).
- Logitech devices (e.g. MX Master) don't report battery to macOS.
- Status item windows are taller than the menu bar on some displays; the deck anchors to the button's
  on-screen rect, not its window (`DeckController.targetFrame`).
- With separate items and a full menu bar, macOS hides some items; the combined item + notch fit is the fix
  today, auto-collapse (P2) later.
- `nettop` takes ~1 s per sample, so per-app network data lags a second and only runs while the Network
  detail is open.
- Weather needs network access to Open-Meteo; only the chosen city's coordinates are sent.
- Keep awake only prevents idle sleep; closing the lid still sleeps the Mac (lid-closed needs root, P3).
- Agent watch notices a brand-new agent session within 5 min (the full folder walk); known files every minute.

---

## 8. Session notes

Newest first; keep about five. Older notes are folded into §3, §6 and §7 (and `git log`).

#### 2026-11-19: P0 QA pass

QA agent on the installed HEAD build. Seen: ring symbol (all states, transition, deck header), wobble motion in the menu bar, ring-only style and badge, tooltip, agent logos, red dot, palette process commands, tile hover. Found and fixed: "Working now" wrapping, and `build.sh` failing on a no-op release build. Not seen: bounce, press / unfold, Settings drags, widgets, the Quit confirmation, chips, most of the P2 batch. The owner still has to do Reduce Motion / Increase Contrast, VoiceOver, Bluetooth sleep and a second Claude account. Before QA, check the running PID started after the install (an old instance kept running once).

#### 2026-11-19: Branded DMG window

Finder on macOS 26+ fights scripted DMG layouts in two ways, both handled in `release.sh` (keep them): about
5 s after the window closes it rewrites `.DS_Store` with its default view settings, so the disk is detached
with the window still open; and `update without registering applications` deletes `.VolumeIcon.icns` and
clears the custom-icon flag, so the volume icon goes on after Finder is done (`hdiutil -srcfolder` drops that
file too). The script now mounts the finished DMG and checks the saved `icvp` (background type 2, icon size
100), so a plain window can't ship silently. Finder draws icon labels black on picture backgrounds, hence the
slate label plates.

#### 2026-11-19: Distribution pipeline and update check

`scripts/release.sh` and the GitHub Releases update check are in (§3, §6); only `--dry-run` could be run, since
this Mac has no "Developer ID Application" certificate (that needs the paid Apple Developer Program). Next: enrol,
create the certificate (same team as the app group, `77HKFF78Z8`), `xcrun notarytool store-credentials
vibecheck-notary …`, run `scripts/release.sh`, then `gh release create v1.5 …`. The repo is private, so the
update check gets a 404 and stays quiet until the repo (or a releases-only repo) is public. Gotcha: under
`set -o pipefail`, `cmd | grep -q` fails when grep exits early (SIGPIPE), so match captured output instead.

#### 2026-11-19: Widgets

Shipped the last P2 feature, desktop widgets, without an Xcode project (§3, §6). The widget extension is
sandboxed and reads `widget-snapshot.json` from the app group container; the main app gained an app group
entitlement but no sandbox. Builds signed with anything but Apple Development skip the widget. Widget strings
are English literals (no catalog in the extension yet). The first install crashed on load (the gallery
just left it out): extensions start in `_NSExtensionMain`, which Xcode sets and SwiftPM doesn't, so
`Package.swift` now passes `-e _NSExtensionMain`. Crash reports land in `~/Library/Logs/DiagnosticReports/
VibeCheckWidget-*.ips`. After the fix the owner saw the medium widget live; the small one is still unseen.

#### 2026-11-19: Tech debt

Cleared the four tech debt items (§3). The deck demo stayed out of `#if DEBUG` on purpose: `build.sh` builds
release and QA runs `--deck-demo` on that build. Settings call sites renamed (e.g. `settings.menuBarStyle` →
`settings.menuBar.style`, `keepAwakeDisplayOn` → `keepAwake.displayOn`); the stored keys did not change. Only
the private-API watch list is left under Tech debt.

---

## How to update this file

At the end of each session, and **whenever a feature is done**:

1. Remove the item from §2 and add it to the top of §3 *Shipped*, with the date and how it was checked
   (unit tests, `--dump`, `pmset`, seen on screen…). Partly done: update its "What's left" in §2.
2. New ideas go into §2's list with a priority; drop anything the owner rejects into "Not planned".
3. Update §4 if anything was checked on screen; never mark something seen that wasn't.
4. Add any decision a future session might be tempted to undo to §6.
5. Add a short dated note to §8 and bump the _Last updated_ line. Keep about five notes; fold lasting lessons
   into §7 and drop the rest.

```markdown
#### YYYY-MM-DD: short title

What was verified and how, what wasn't, anything the next session should know.
```
