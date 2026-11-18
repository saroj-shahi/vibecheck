# VibeCheck improvement plan

A living log for future work sessions. **Read this first**, then add to it at the end of each session
(see [How to update this file](#how-to-update-this-file)).

_Last updated: 2026-11-18 · version 1.5 · 14 commits · ~5,900 lines of Swift · 43 tests_

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

- **Performance budget.** Last measured ~0.7–3.6% CPU and 90–140 MB. Profile with Instruments, then:
  - `ps` runs every tick while the deck home is open (for the verdict's "loudest app"); drop to every 5 s.
  - `refitAroundNotch()` builds one `NSHostingView` per module to measure widths; cache widths per
    module + style + spacing.
  - Check SwiftUI redraw cost of menu bar labels at a 1 s interval.
- **Distribution.** Developer ID signing + notarization (`notarytool`), a DMG, and an update mechanism
  (Sparkle or a GitHub Releases check). Today it's ad hoc signed, so other Macs need right-click → Open.
- **Swift 6 language mode.** The package uses tools 5.10 / language mode 5. Turn on strict concurrency
  and fix warnings (most code is already `@MainActor`; samplers hop through `DispatchQueue.global`).
- **Separate-items reorder.** Moving modules in Settings doesn't move existing separate items (macOS keeps
  autosaved positions). Either document ⌘-drag (done in the UI) or recreate items with new autosave names.

### P2

- **Liquid Glass `.icon`** made in Icon Composer from `branding/svg/icon.svg` layers (keep the `.icns`
  for macOS 14–15).
- **App Intents / Shortcuts:** "Get Mac vibe", "Get CPU usage", "Open VibeCheck deck".
- **WidgetKit widgets:** vibe ring, CPU/memory sparkline (needs an app group to share samples).
- **Notification history** in the deck (last 20 alerts with time and value).
- **Network:** public IP (opt-in, privacy note), Wi-Fi details (SSID needs Location permission),
  per-app traffic history.
- **Battery:** charge history over days, health trend.
- **Localization:** strings are inline English; move to a String Catalog.
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
