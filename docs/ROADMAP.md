# VibeCheck roadmap

The one planning file for VibeCheck: what's next and in what order, what has shipped, what has been seen
working, the design rules and the decisions behind them. **Read sections 1 and 2 first**, then the rest
only for the area you're touching. Code locations are in [CODEMAP.md](CODEMAP.md); brand, voice and motion
in [BRAND.md](../branding/BRAND.md) (it wins over this file on those).

_Last updated: 2026-11-18 · version 1.5 · ~11,100 lines of Swift · 164 tests_

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

**Biggest open gaps:** on-screen checks of light mode, animations, Reduce Motion and VoiceOver (P0);
nobody else can install it (P1 distribution); the ring-first menu bar isn't the default yet (P1).

---

## 2. Roadmap

### P0: verify what's shipped

On-screen QA needs the owner to keep hands off the Mac (see "On-screen QA" in §7).

| Feature / check | Status | Notes |
|---|---|---|
| Deck: light mode, tile hover and press, unfold / fold animation | ⬜ | Dark mode, Esc, arrows, ⌘1/⌘2/⌘6/⌘0 done |
| Vibe ring bounce | ⬜ | Colors seen (yellow mid, red cooked) |
| Ring badge ("CPU 96%") and verdict tooltip on the installed app | ⬜ | Built and installed 2026-11-18; the ring's new label shows up in the accessibility tree |
| Agent watch: session ends after 3 quiet minutes; "is done" notification | ⬜ | Trigger start seen with `pmset` |
| Settings: drag to reorder, number drag, banner preview | ⬜ | Reorder skipped so far: it would change the owner's order |
| Reduce Motion and Increase Contrast: readable, springs become fades | ⬜ | |
| Real VoiceOver over deck, menu bar items, palette; alert number adjustable | 🟡 | Tiles read as sentences in the accessibility tree |
| Bluetooth off while asleep: permission prompt, really off in sleep and back on after wake | ⬜ | Owner will test: switch it on in Settings → General, sleep, wake, check the log (§7) |
| Quit / Force Quit menus and confirmation, mic-muted and shortcuts-paused chips, notification red dot | ⬜ | Unit-tested only |

Fix whatever turns up before starting new features.

### P1: soon

| Feature | Status | Why | Main files |
|---|---|---|---|
| **Ring-first menu bar for new installs:** one ring item by default; existing users keep their choice | ⬜ | One slot beside the notch; also the cheapest fix for idle CPU (it scales with item count) | `App/AppSettings.swift`, `App/AppDelegate.swift` |
| **Cup in the ring's gap** instead of a second item while keep-awake runs (standalone cup stays an option) | ⬜ | One item instead of two | `Views/VibeRing.swift`, `Views/CombinedViews.swift` |
| **Distribution:** Developer ID signing, notarization (`notarytool`), DMG, update check (Sparkle or GitHub Releases), Homebrew cask | ⬜ | Nobody else can install it today. The Apple Development cert (Team ID `77HKFF78Z8`) expires Nov 2027 | `build.sh` |

### P2: nice to have

**Menu bar and deck**

| Feature | Status | Notes |
|---|---|---|
| Auto-collapse to the combined item when macOS hides a separate item behind the notch, with a one-time plain notice | ⬜ | Detect via the item window's frame vs `auxiliaryTopLeftArea` / `TopRightArea`; `App/NotchFit.swift` has the maths |
| ⌥-click the ring to toggle keep awake | ⬜ | Matches the cup's click |
| Drop a file / folder on the ring: awake until it finishes; drop an app: awake while it runs | ⬜ | Needs `registerForDraggedTypes` on the button; reuse `DownloadsWatcher` and the app trigger. Ring dilates 10% while hovered |
| Six tiles by default (CPU, Memory, Network, Sensors, Battery, Agents); Clock and Weather off for new installs | ⬜ | Never reorder tiles by severity; the culprit outline points |
| Empty Trash leaves the quick toggles for ⌘K | ⬜ | Fails "does this need to be in the menu bar?" |
| Discoverable gestures: cup tooltip names the hold dial; one dismissible hint line after an update | ⬜ | |
| Settings audit: anything not changed in the first week goes under "Advanced" | ⬜ | |
| Palette: "recent" ordering; process ("Quit Chrome") and alert commands with the same confirmation rules | ⬜ | ⌘↩ is where the second step goes |
| Quick toggle failure shake (3 pt, 240 ms) and symbol replace transition | ⬜ | |

**Features that reuse what VibeCheck knows**

| Feature | Status | Notes |
|---|---|---|
| **Call guard:** camera / mic in use holds non-critical alerts, keeps the display awake, warns before a call stutters ("Xcode is at 140% CPU. Quit Xcode?") | ⬜ | `kCMIODevicePropertyDeviceIsRunningSomewhere`, `kAudioDevicePropertyDeviceIsRunningSomewhere`; Focus filter (`SetFocusFilterIntent`); same Quit rules |
| **Vibe replay:** record mid / cooked episodes with culprit and duration; 24 h vibe strip; "Chrome Helper cooked your Mac 4 times this week" | ⬜ | `App/Vibe.swift`, `App/HistoryStore.swift` |
| Keep awake "while on Wi-Fi X" | ⬜ | SSID needs Location permission |
| Network: public IP (opt-in, privacy note), Wi-Fi details, per-app traffic history | ⬜ | |
| Battery: charge history over days, health trend | ⬜ | |
| WidgetKit widgets: vibe ring, CPU / memory sparkline | ⬜ | Needs an app group to share samples |

**Polish and presence**

| Feature | Status | Notes |
|---|---|---|
| Recovery check: cooked / mid → vibing draws the brand's pulse-to-check through the ring's gap once | ⬜ | Trim 0 → 1, spring 0.5 / 0.75; Reduce Motion 150 ms crossfade; never on launch |
| Culprit drain: after quitting the culprit, its number rolls down, the outline drains (400 ms), the ring refills | ⬜ | |
| Localization: inline English strings → String Catalog | ⬜ | |
| Liquid Glass `.icon` from Icon Composer (keep `.icns` for macOS 14–15) | ⬜ | From `branding/svg/icon.svg` layers |
| Website / landing page from the brand assets | ⬜ | |
| GitHub social preview: upload `branding/png/social-card.png` | ⬜ | Manual, repo settings |

### P3: someday / risky

| Feature | Notes |
|---|---|
| Fan control | Privileged helper (`SMAppService.daemon`) writing SMC keys; a bug can affect cooling. Only with explicit owner sign-off and a hard safety floor |
| Disk cleaner | Start read-only (reclaimable caches in the Disk view); deleting needs a review step and never touches documents |
| Display brightness | External monitors need DDC over private APIs |
| Calendar in the Clock panel | Needs calendar permission; widens scope |
| Keep awake with the lid closed | Needs root (`pmset disablesleep`); same sign-off as fan control |
| iCloud settings sync | Watch conflicts with per-Mac settings like notch fit |
| Custom SF Symbol for the menu bar ring | Variable value, template rendering; may lower redraw cost |
| Sandboxed App Store edition | Private APIs (HID temps, SMC, IOBluetooth) and `ps` / `lsof` / `nettop` rule out the sandbox; needed for the App Store (and so for an Apple Design Award) |

**Not planned:** another app's window, Dock, mouse, keyboard, clipboard, file, screenshot, recording,
uninstaller, lyrics and companion tools, its "Dynamic Island" bar, and API cost estimates (needs a price
list; owner said no).

### Tech debt

- `Views/Panels.swift` is large; split per module.
- `AppDelegate.runDeckDemo()` is debug code in the app target; move behind `#if DEBUG` or a debug file.
- `AppSettings` keeps growing; group into sub-objects (menu bar, alerts, clock, weather).
- `ClockFormatStyle` caches formatters in a `nonisolated(unsafe)` static; add a lock if used off the main thread.
- Private / undocumented APIs, all looked up at runtime with fallbacks: `IOHIDEventSystemClient*`
  (temperatures), `responsibility_get_pid_responsible_for_pid` (app grouping), SMC keys `PSTR`/`PDTR`/`F0Ac`,
  `IOBluetoothPreference{Get,Set}ControllerPowerState`. Re-check after each macOS update.

---

## 3. Shipped

Newest first. Versions 1.0–1.5 (the ten monitors, deck, Settings, alerts, history, notch fit, Shortcuts
actions, keep awake, notification history) are in `git log` and the README.

| Date | Feature | How it was checked |
|---|---|---|
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
| Tile hover / press, unfold animation, ring bounce | ❌ never seen |
| Chart scrubbing bubble | ✅ seen with synthetic mouse moves |
| Range morph, peak haptic, drag-to-adjust numbers | ❌ never touched |
| Deck keys: Esc, arrows, ⌘2 | ✅ synthetic key events |
| Global shortcuts ⌃⌥⌘1–9 from another app | ✅ ⌃⌥⌘2 opened GPU; others not tried |
| Notifications appearing | ✅ test banner seen by the owner; permission prompt not seen |
| Notch auto-fit on the built-in display | ⚠️ maths verified with real widths, not seen |
| Settings: all 8 panes, live preview | ✅ seen |
| Settings: drag to reorder, number drag, token menus, banner preview | ❌ not touched |
| Launch at login across a real restart | ⚠️ registered, not rebooted |
| Keep awake: assertion held (display / system type) and released | ✅ `pmset -g assertions` + a unit test reading `IOPMCopyAssertionsByProcess` |
| Keep awake: deck cup menu, menu bar cup, Settings pane, status strip | ✅ seen ("Until" submenu not opened) |
| Keep awake triggers: plugged in, external display, downloading, schedule | ✅ built app with launch arguments + `pmset -g assertions` |
| Keep awake "while an AI agent is working": assertion ~3 s after launch while Claude Code wrote logs; none with it off | ✅ built app with launch arguments + `pmset` (2026-11-18). Ending and the "is done" notification: unit tests only |
| Keep awake: ending on unplug / display removal, end notification, ⌃⌥⌘A, "Until" menu | ❌ unit tests only |
| Ring badge beside the menu bar ring; verdict tooltip on hover | ❌ installed, not seen (accessibility label confirmed by `qa item Vibe`) |
| App Intents metadata in the bundle | ✅ `extract.actionsdata` inspected |
| Shortcuts app lists the 5 actions | ✅ seen by the owner; running them, Spotlight and Siri not tried |
| Idle CPU / memory with the deck closed: ~3.3% / ~100 MB | ✅ installed app, 3× 40 s with `ps` |
| Detail views: CPU, GPU, Battery, Network (+ ports), Sensors, Agents | ✅ seen; Weather not (module off) |
| Swift 6 language mode: no warnings, no runtime isolation crashes in an 80 s run | ✅ |
| Notification history: logic; bell and empty popover | ✅ unit tests; seen. Red dot and filled list ❌ |
| Agents: token totals from real logs, menu bar item, tile, cards, gauges, plan badges, Now card | ✅ `--dump` + seen |
| Live Claude limits from the real CLI | ✅ probe test + real menu bar values |
| Copilot CLI / OpenCode parsing and quota | ✅ unit tests + `--dump` |
| 7-day chart, limits gauges with sample data | 🟡 offscreen renders |
| Per-item options: logic and migration; panel | ✅ unit tests; panel rendered offscreen, not seen expanded |
| Bluetooth off while asleep: private calls, permission read, `--dump` line | ✅; prompt, toggle and real sleep ❌ |
| Quit / Force Quit: rules and real child process | ✅ unit tests; menus and confirmation ❌ |
| Secure input detection | ✅ probe test; warning and deck line ❌ |
| Listening ports: `lsof -F` parsing; section in the deck | ✅ 7 unit tests; seen (quit not tried) |

---

## 5. Design rules

Condensed from three reviews: the "menu bar Creative Director" brief (round one), a popover
mockup (`docs/otherapp-popover-mockup.html`, a different app, round two) and the Apple Design Award style
teardown (round three). BRAND.md still decides voice, color and motion.

**The idea.** A verdict first and a cockpit second, in a 360 pt sheet of glass. Everything folds behind three
doors: **tile → detail**, **cup → menu**, **⌘K → anything**. Before adding UI, ask whether it can be a palette
command.

**What the ADA teardown said (round three).** Award-grade: the verdict-first idea, the single non-activating
deck, the drawn ⌘K field, the culprit outline. Holding it back: too many jobs at once (Empty Trash, Clock
and Weather fail the menu bar test), separate items a notched MacBook will evict, idle cost that scales with
item count, hidden gestures, unverified accessibility, no distribution. The §2 items marked P1/P2 under
"Menu bar and deck", call guard and vibe replay come from it. Full text: [the appendix](#appendix-vibecheck-the-ada-teardown-and-roadmap).

**Menu bar**
- Monochrome by default; color only when the vibe isn't vibing. Width is earned the same way: the ring
  grows a badge only on mid / cooked, and not when the culprit has its own item.
- A status item's length is never re-measured by macOS: set it explicitly whenever content changes shape.
- Haptics only fire with a finger on a Force Touch trackpad: use them for direct manipulation (dial
  detents, chart peaks), never for background events.

**The deck shell, top to bottom** (360 pt wide, never wider)

| Zone | Height | Rule |
|---|---|---|
| Header | ~50 pt | Ring + verdict title, then only bell and cup |
| Search field | 28 pt | Always visible, drawn (the panel never takes focus); ⌘K key cap; click it or just type |
| Live chips | 0 or 26 pt | One pill per thing happening now (keep awake / focus, mic muted, shortcuts paused); hover shows × to stop; absent when nothing is live |
| Body | flexible | Quick toggles (one row, max three) + bento grid, or palette results |
| Footer | 30 pt | Settings (⌘,) · version · Quit; key hints and result count while the palette is open |
| Detail view | up to the screen | Matched-geometry unfold; pinned header; lists cap at 8 rows + "+N more" |

- Tiles: 3 columns, 8 pt gutters, (360 − 32 − 16) / 3 = **104 pt** so edges land on whole pixels. One hero
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
swift scripts/render_brand.swift # regenerate icon and brand assets from branding/svg
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

#### 2026-11-18: one roadmap

Merged `IMPROVEMENT_PLAN.md` and `DESIGN_DIRECTION.md` into this file, ordered by feature priority. CLAUDE.md,
README and CODEMAP point here.

#### 2026-11-18: cleanup

Removed the unused QA helpers `crop`, `grid` and `pos`. `qa item` matches the item description by prefix. A
scan of types, statics and member names found no other dead Swift code. The owner deleted the old
`local.pulse.monitor` settings (an empty plist file is left in `~/Library/Preferences`).

#### 2026-11-18: agent watch, ring badge, verdict tooltip

Built from the ADA review; installed and relaunched. Reviewer fixes: the ring re-measures only on a badge
shape change; a run cut by midnight is dropped without notifying. A run's length counts from the first write
VibeCheck saw.

#### 2026-11-18: ADA-style design review

Review only. Main points are in §5; the resulting work is in §2.

#### 2026-11-18: QA of the new deck

Installed build checked on screen by the QA agent (round-two rows in §4). Fix from it: ⌘↩ on a row whose only
action is Run beeps instead of showing a one-item card.

---

## Appendix: VibeCheck, the ADA teardown and roadmap

The full Apple Design Award style review from 2026-11-18, kept as written. Its work items live in §2 (and
§3 once done); paths are relative to `Sources/VibeCheck/`. Where this appendix and §2 differ, §2 is current.

### 1. 🔍 The brutal (but fair) teardown

**What's award-grade already**
- **Verdict first.** "Vibing / mid / cooked" plus one sentence naming the culprit is a real idea. Most
  monitors hand you a wall of gauges; this one hands you an answer. The culprit outline on the tile
  ("the verdict says why, the grid says where") is the best detail in the app.
- **The deck architecture is right.** One borderless non-activating `NSPanel` instead of `NSPopover`,
  matched-geometry unfolds, 104 pt whole-pixel tiles, glass used once, a drawn ⌘K field so the panel never
  steals focus. That's Apple-level thinking.
- **Honest engineering.** IOKit assertions instead of a `caffeinate` child, pid start-time checks before
  killing, two-sample hysteresis on the ring, App Intents shipped, and a verified/not-verified table.

**What would get it cut in the first round**
1. **It doesn't know what it is.** It's a system monitor, a keep-awake app, a focus timer, a
   quick-toggle strip (Dark mode, Mic, *Empty Trash*), a process killer, a port manager, a USB lister, a
   Bluetooth sleep tool, an AI token tracker, a clock and a weather app. Each one is fine. Together they
   tell a judge "feature list," not "point of view." **Empty Trash in a system monitor** is the clearest
   case: it fails the "does this need to be in the menu bar?" test outright.
2. **Clock and Weather fail the menu bar test.** macOS already owns the clock at the right edge, and
   Weather has a widget plus Notification Center. They cost tiles, Settings panes and network code and add
   nothing to the verdict. Demote them.
3. **The owner's own setup breaks the notch.** Separate items for CPU, GPU, Network, Sensors, Battery and
   Agents, plus ring and cup, is about 8 items. On a 14" MacBook that's a guaranteed eviction behind the
   notch, and the app only addresses it when the user picks "combined." The default should be smart
   enough that nobody has to know the notch exists.
4. **Idle cost is too high for a "glance" app.** ~3.3% CPU and ~100 MB with the deck closed. The docs
   correctly blame `NSStatusItem _updateReplicants` redrawing every item's `NSHostingView` on every display,
   so the real lever is **fewer, calmer items**, not a faster renderer. Six live-updating items × two
   displays is the cost.
5. **Hidden gestures.** Press-and-hold on the cup for a four-sector dial, right-click vs click on the cup
   item, ⌥-click: powerful, but undiscoverable. ADA judges try things once.
6. **Polish is unproven on screen.** Light mode hover/press, the unfold animation, ring bounce, Reduce
   Motion, Increase Contrast and real VoiceOver have never been seen. Accessibility is a judging
   criterion, not a nice-to-have.
7. **Nobody else can install it.** No Developer ID, no notarization, no DMG, no updates. And the honest
   blocker: ADA entries come from the App Store, and VibeCheck's private APIs (`IOHIDEventSystemClient`,
   SMC keys, private IOBluetooth) plus shelling out to `ps` / `lsof` / `nettop` are incompatible with the
   sandbox. "Award-grade" is the bar to hold; the trophy itself would need a sandboxed edition.

---

### 2. ⚠️ The notch and menu bar strategy

**The icon: one ring that earns its width.**
- **Default to a single item: the vibe ring.** ~18 pt, monochrome template look, no text while vibing.
  When the vibe goes mid or cooked, the item grows to **ring + culprit + number** ("◔ CPU 96%"), and shrinks
  back when it recovers. Width is earned by bad news, same rule the deck uses for color.
  - Code: `StatusItemController` in `App/AppDelegate.swift` already sets `item.length = max(ceil(width), 8)`
    (line 142). The "Limits left" clipping bug came from length being measured only at creation, so this
    must set `length` explicitly on each vibe change (which already passes the two-sample hysteresis, so
    it can't flicker).
- **Fold the cup into the ring.** While keep-awake runs, the ring gets a small cup badge in its gap (the
  gap the brand reserves for the check). One item instead of two. The standalone cup stays an option.
- **Auto-collapse when evicted.** Separate-items users keep their layout until macOS actually hides an
  item. Detect it (status item window frame off-screen or overlapping `NSScreen.auxiliaryTopLeftArea` /
  `auxiliaryTopRightArea` on the notched display), then fall back to the combined item with a one-time
  notice: "Some stats didn't fit beside the notch, so VibeCheck combined them." `App/NotchFit.swift` has
  the maths; this adds detection.
- **Calm redraws.** Items that show a number redraw at the refresh rate; the ring only redraws on a state
  change. Making the ring the default is also the cheapest fix for the idle-cost problem in §1.4.

**Interactions on the icon**
| Gesture | Does |
|---|---|
| Click | Open the deck (unchanged) |
| ⌥-click | Toggle keep awake with the default length (matches the cup's click) |
| Right-click | Compact menu: verdict sentence, keep-awake options, Settings, Quit |
| Hover | Tooltip with the verdict sentence ("Kinda mid: memory is getting tight.") via `button.toolTip`, the cheapest win on this list (none today) |
| **Drop a file or folder** | "Keep awake until this finishes": watches that path for growth/renames, reusing the downloads-watcher trigger in `App/DownloadsWatcher.swift` |
| **Drop an app** | "Keep awake while *App* runs", reusing the existing app trigger in `App/KeepAwake.swift` |

Drag-and-drop needs `registerForDraggedTypes` on the status button (none today). It makes keep-awake a
one-gesture feature instead of a menu dive, which is exactly the "zero friction" bar.

---

### 3. 🌟 "App of the Year" feature injections

**A. Agent watch: "keep awake while my agent works."** *(reuses `AgentUsage.isWorking`, KeepAwake triggers)*
VibeCheck already knows when Claude Code / Codex / Copilot / OpenCode is "working now" from local logs. Add a
keep-awake trigger "While an AI agent is working" (edge-triggered like the others, manual Stop still wins),
plus an opt-in "Agent finished" notification when work stops after a long run. Close the lid on a
20-minute agent run and come back to a finished job instead of a sleeping Mac. No other monitor can do this
because no other monitor reads agent logs. It's the feature that gives the Agents module a reason to live
in a system monitor.

**B. Call guard: protect the meeting.** *(new, public APIs)*
Detect a call: camera in use (`kCMIODevicePropertyDeviceIsRunningSomewhere`) or mic in use
(`kAudioDevicePropertyDeviceIsRunningSomewhere`). While on a call: hold non-critical alerts until it ends,
keep the display awake, and if the vibe goes mid, say so *before* the call stutters, with one action:
"Your call may stutter: Xcode is at 140% CPU. Quit Xcode?" (same Quit rules, pid start-time check, second
confirmation). Add a **Focus filter** (`SetFocusFilterIntent`) so users choose per Focus whether alerts
are held. This turns VibeCheck from "tells you it's cooked" into "keeps it from getting cooked when it
matters."

**C. Vibe replay: the Mac's memory.** *(reuses `HistoryStore`, `Vibe`, `AlertEngine` history)*
Record each mid/cooked episode with its culprit and duration. The ring's detail (click the ring in the
deck header) shows a 24 h strip colored by vibe and a line like "Chrome Helper cooked your Mac 4 times this
week, 52 min total." Repeat offenders get a one-tap action (Quit, or an alert rule pre-filled for that app).
It answers the question users actually have: not "what is the CPU now," but "why was my Mac slow this
afternoon?"

Not proposed on purpose: more modules. Every injection above reuses data VibeCheck already collects.

---

### 4. ✨ The ADA-level interface and polish

**Layout: subtract before adding**
- **Home grid caps at six tiles.** Default modules: CPU, Memory, Network, Sensors, Battery, Agents. GPU and
  Disk on by choice; Clock and Weather off by default and reachable only through ⌘K and Settings.
- **Never reorder tiles by severity.** Spatial consistency beats drama; the culprit outline already points.
- **Quick toggles: Dark and Mic only.** Empty Trash moves to ⌘K (still behind Finder, per the decisions log).
- **Discoverable gestures.** The cup's tooltip says "Click for options · hold to pick a length". First time
  the deck opens after an update, one dismissible line under the search field shows the new gesture, never
  again.
- **Settings stays behind ⌘,** (already right). Audit the 8 panes against "would a user change this in the
  first week?" and move the rest under an "Advanced" disclosure.

**Visuals**
- Keep what's there: `NSGlassEffectView` on 26+, `NSVisualEffectView` `.popover` / `.behindWindow` with the
  0.5 pt hairline on 14–15, quiet `.quaternary` tiles. Don't add a second glass layer anywhere.
- **Make the ring a custom SF Symbol** (exported from the SF Symbols app with a variable-value layer) for
  the menu bar. It matches the menu bar's weight and size automatically, renders as a template, scales with
  Dynamic Type-like settings, and gets `symbolEffect` transitions for free instead of hand-built shapes in
  an `NSHostingView`, which also lightens the replicant redraw cost.
- Type stays as specified: SF Pro Text 15 pt semibold verdict, SF Pro Rounded 17 pt monospaced-digit
  heroes, 10 pt minimum.

**Micro-interactions**
1. **The recovery check.** When the vibe goes from cooked or mid back to vibing, the ring refills and the
   brand's pulse-to-check stroke draws through the gap once (trim 0 → 1, spring 0.5 / 0.75) then fades,
   in the menu bar and in the deck header. It's the logo becoming the verdict. Reduce Motion: a 150 ms
   crossfade. Once per recovery, never on launch.
2. **Quitting the culprit.** After a Quit from the culprit tile, the hero number rolls down with
   `numericText`, the red outline drains around the tile (stroke trim reversing over 400 ms), and the ring
   in the header refills. The user sees cause and effect in one beat.
3. **Drop target.** While a file or app is dragged over the menu bar, the ring dilates 10% and the cup
   fades into its gap; release snaps it with spring 0.2 / 0.7.

**On haptics, an honest correction to the brief:** `NSHapticFeedbackManager` only fires while a finger is
on a Force Touch trackpad. Use it for direct manipulation (the hold dial's sector detents, already done;
chart scrub peaks), never for background events like a task finishing.

**Accessibility (P0, not polish):** run real VoiceOver over the deck, menu bar items and palette; Reduce
Motion and Increase Contrast passes; the menu bar item's accessibility label should read the verdict
sentence, not "CPU 96".

---

### 5. 🏆 The winning pitch

VibeCheck is the first Mac monitor that answers a question instead of showing a dashboard: one ring tells
you if your Mac is vibing or cooked, and one click names the culprit and fixes it. It takes one slot beside
the notch, protects your calls and your AI agents' runs without being asked, and feels like Apple built it
for people who never want to think about a process viewer again.

---

## How to update this file

At the end of each session, and **whenever a feature is done**:

1. Move the feature's row from §2 to the top of §3 *Shipped*, with the date and how it was checked
   (unit tests, `--dump`, `pmset`, seen on screen…). Partly done: mark it 🟡 in §2 and say what's left.
2. New ideas go into §2 with a priority; drop anything the owner rejects into "Not planned".
3. Update §4 if anything was checked on screen; never mark something seen that wasn't.
4. Add any decision a future session might be tempted to undo to §6.
5. Add a short dated note to §8 and bump the _Last updated_ line. Keep about five notes; fold lasting lessons
   into §7 and drop the rest.

```markdown
#### YYYY-MM-DD: short title

What was verified and how, what wasn't, anything the next session should know.
```
