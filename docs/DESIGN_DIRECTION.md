# VibeCheck design direction

Creative direction for the deck, written with the owner's "menu bar Creative Director" brief
(`~/Desktop/menu_bar_creative_director_prompt.md`). It builds on [BRAND.md](../branding/BRAND.md), which
still decides voice, color and motion; where they differ, BRAND.md wins. Status markers: ✅ shipped,
🟡 partly, ⬜ not yet.

---

## 1. 👁️ The Creative Vision

VibeCheck is a verdict first and a cockpit second. Everything has to fit in a 360-point sheet of glass
that drops from the menu bar: one ring, one sentence, then a calm bento of live tiles. We tame the bloat
by never letting a feature claim pixels it hasn't earned. Ten modules, keep-awake, focus, toggles, process
control and a whole Settings window all fold behind three doors: **tile → detail**, **cup → menu** and
**⌘K → anything**.

## 2. 🏗️ Popover Architecture & Progressive Disclosure

The deck is **360 pt wide, never wider**. Every directive below exists to protect that width.

| Zone | Height | Contents | Rule |
|---|---|---|---|
| Header | ~56 pt | Vibe ring (30 pt) + verdict title, icon buttons (search, bell, cup, gear, power), the verdict sentence on its own line | Icon buttons are 26 pt hit circles, no labels. The verdict never shares a line with buttons. ✅ |
| Status strips | 0–2 × 32 pt | Keep-awake session, "Shortcuts paused" | Only exist while true. Never more than two; they're facts, not settings. ✅ |
| Quick toggles | 28 pt | Dark, Mic, Trash chips | One row, max three. A fourth toggle goes in ⌘K, not in this row. ✅ |
| Bento grid | 3 columns × 76 pt tiles, 10 pt gutters | One tile per enabled module: icon + title, one hero number, one sparkline *or* one detail line | Tiles never grow a second number. Detail lives one click deeper. ✅ |
| Detail view | up to the screen | Matched-geometry unfold of one tile: chart, ranges, lists | Esc folds back. Lists cap at 8 rows plus "+N more". ✅ |
| **Command palette** | search row 36 pt + up to 8 rows × 30 pt | Every action in the app, typed | ⌘K, or just start typing on the home grid. ✅ (2026-11-18) |

**Fighting visual overload:**

- **⌘K is the escape valve.** Opening a module, starting keep-awake or focus, flipping Dark or Mic,
  jumping to any Settings pane and quitting are all reachable by typing, so none of them needs a new
  button. Before adding UI, ask: can this be a palette command instead?
- **Type-to-act.** On the home grid any letter opens the palette already filtered, like Spotlight. Arrows
  and Return keep driving the grid; ⌘-digits keep opening modules.
- **One hero number per tile.** Secondary numbers belong to the detail view or the tooltip.
- **Settings stays a separate window.** The deck never shows a configuration control except the quick
  toggles.

## 3. 🎨 The macOS Palette & Typography

**Materials**

- macOS 26+: `NSGlassEffectView` with an 18 pt continuous corner radius. Glass appears **once**: tiles,
  chips and rows use quiet fills (`.quaternary` at 55%, 90% on hover), never nested glass. ✅
- macOS 14–15: `NSVisualEffectView`, material `.popover`, `.behindWindow`, plus a **0.5 pt inner hairline**
  so the edge reads as glass instead of a blur blob: white at 10% in dark mode, black at 8% in light mode,
  stroked inside the 18 pt shape. ✅ (2026-11-18). Liquid Glass draws its own edge, so it doesn't get the hairline.

**Type** (SF Pro; never a custom font in the UI)

| Role | Spec |
|---|---|
| Verdict title | 15 pt semibold, SF Pro Text |
| Tile hero number | 17 pt semibold, **SF Pro Rounded**, `monospacedDigit()`, tracking −0.2, `numericText` transition |
| Tile title, palette row | 11 / 13 pt medium, `.secondary` / `.primary` |
| Section labels | 11 pt semibold, sentence case |
| Key caps (⌘1, esc, ↩) | 10–11 pt medium, SF Pro Rounded, `.tertiary`, 4 pt radius capsule at `.quaternary` |

**Color logic**

- Module accents are system-adaptive colors (they follow light/dark and Increase Contrast). The accent
  appears on the tile's icon and sparkline only.
- **State color is earned:** mint / yellow / red only for vibing / mid / cooked and real warnings (orange
  for "paused" facts). The menu bar stays monochrome until the vibe isn't vibing.
- The palette's selected row uses `Color.accentColor` at 14% fill. The user's system accent is the only
  "brand" color in interactive states, so the app looks native on every Mac.

## 4. ✨ Menu Bar Micro-Interactions

1. **Tile hover reveal.** *Trigger:* the pointer enters a tile. *Change:* the fill goes from 55% to 90%
   `.quaternary`, and a 9 pt `chevron.right` fades in at the tile's top-right corner (opacity 0 → 0.6,
   2 pt slide from the left). *Easing:* 150 ms ease-out in, 120 ms ease-out out. It tells you the tile
   opens without adding a permanent glyph to every tile. ✅ (2026-11-18)
2. **Palette selection.** *Trigger:* ↑/↓ or hover over a row. *Change:* the 14% accent fill moves to the
   row, and a `return` key cap fades in at the trailing edge, replacing that row's shortcut hint.
   *Easing:* 120 ms ease-out. Reduce Motion: instant. ✅ (2026-11-18)
3. **Press.** *Trigger:* mouse down on a tile. *Change:* scale to 97%. *Easing:* spring 0.2 / 0.7, so it
   springs back on release (BRAND.md §7). ✅

Not changed: the deck's open animation (anchored drop from the status item, 0.38 s, curve
0.2/0.9/0.1/1.0) and the tile → detail unfold (spring 0.38 / 0.86, staggered 25 ms). Both are already
specified in BRAND.md.

## 5. 🏆 The Benchmark (Stolen from the Best)

- **launcher apps: the command bar.** We take three things: type anywhere to search, a selection that moves
  with the keyboard while the mouse still works, and shortcut hints on the right of every row. We
  leave the rest: no extensions, no plugin store, no second window. The palette lives inside the deck
  and disappears with it.
- **dense menu bar monitors: density with dignity.** One number per tile in rounded monospaced digits, sparklines
  with no axes, and detail one click away. We skip its menu-of-menus structure; matched-geometry unfolds
  replace nested dropdowns.

---

## Round two (2026-11-18): precision, and the outside reference

A second pass with the same brief, using the owner's popover mockup
(`docs/otherapp-popover-mockup.html`, a different app) as the reference for the shell. Where this
section and the ones above differ, this one is newer.

**The shell, top to bottom** (home and palette; a detail view keeps its own header with the back chevron):

| Zone | Height | Rule |
|---|---|---|
| Header | ~50 pt | Ring + verdict title, then only **bell and cup**. Search, Settings and Quit moved out. ✅ |
| Search field | 28 pt | Always visible, drawn (the panel never takes focus): placeholder "Search or run an action" and a ⌘K key cap; click it or just type. While the palette is open it shows the query and caret. ✅ |
| Live chips | 0 or 26 pt | One pill per thing happening now: keep awake / focus (accent, time left), mic muted (red), shortcuts paused (orange). Hover shows × to stop. Replaces the 32 pt status strips; the row doesn't exist when nothing is live. ✅ |
| Body | flexible | Quick toggles + bento grid, or palette results. |
| Footer | 30 pt, 0.5 pt top hairline | Settings (⌘,) · "VibeCheck 1.5" · Quit. While the palette is open it becomes key hints (↩ ⌘↩ esc) and the result count. ✅ |

**Precision**

- **Whole-pixel tiles.** 8 pt gutters: (360 − 32 − 16) / 3 = **104 pt** tiles, so edges land on whole pixels at 1× and 2×. ✅
- **10 pt minimum type.** The 9 pt hover chevron is now 10 pt. ✅
- **Display-aware hairline.** 0.5 pt at 2×; at 1× it's 1 px at half the opacity, because 0.5 pt on a 1× display is a smear. ✅

**Micro-interactions**

1. **The culprit tile.** When the vibe is mid or cooked, the tile of the module behind the verdict gets a
   1 pt inner stroke in the state color at 40% (240 ms ease-out in, 400 ms ease-in out). When cooked, the
   hero number turns red too; mid stays outline-only because yellow text is unreadable on light glass. The
   verdict says *why*; the grid says *where*. ✅
2. **Live chip stop.** Hovering a chip fades in an 18 pt × (150 ms ease-out); clicking it stops the session or
   unmutes. ✅
3. **⌘↩ actions.** On a palette row, ⌘↩ opens a small action list (Run, and the matching Settings pane);
   ↑↓ ↩ drive it, esc closes it. ✅

**Taken from another app, left out on purpose:** its four-column toggle tiles (our tiles carry data), blue
accent fills on active tiles (state color is earned), grouped results while typing (a flat ranked list is
faster), its 12 pt radius and web fonts.

## Backlog from this direction

- ✅ **Keep-awake hold dial** (from another app, 2026-11-18): click the cup for the native keep-awake menu
  (same as the menu bar item's right-click); press and hold 350 ms for a four-sector dial, drag up / right /
  down / left for 15m / 1h / 4h / ∞, release to start. Release in the 12 pt dead zone cancels.
- ✅ Pinned header (2026-11-18): a detail view's back / icon / title row sits above the scroll view.
  Skipped: the separator that fades in once content scrolls (needs scroll offset; `onScrollGeometryChange` is macOS 15+).
- ⬜ Palette: "recent" ordering (last 3 commands first) once there's a reason to remember them.
- ⬜ Palette commands for process actions ("Quit Chrome") and alerts, with the same confirmation rules;
  ⌘↩ is where their second step goes.
- ⬜ Quick toggle chip failure shake (3 pt, 240 ms) and symbol replace transition.
- ⬜ Light mode pass on screen (still unverified, see the plan's P0).

---

## Round three (2026-11-18): the ADA teardown

A third review, written as an Apple Design Award judge would read the app, summarized here. Nothing below
is built yet (all ⬜). Where this section and the ones above differ, this one is newer.

**Verdict on the current app.** The verdict-first idea, the single non-activating deck, the drawn ⌘K field
and the culprit outline are award-grade. What holds it back: too many jobs at once (Empty Trash, Clock and
Weather fail the "does this need to be in the menu bar?" test), separate items that a notched MacBook will
evict, ~3.3% idle CPU driven by how many items redraw, hidden gestures (cup hold dial, click vs right-click),
unverified accessibility, and no way for anyone else to install it. ADA entries come from the App Store,
and the private APIs plus `ps` / `lsof` / `nettop` rule out the sandbox: aim for the bar, not the trophy,
unless a sandboxed edition is made.

**Menu bar: one ring that earns its width.**
- 🟡 Ring that earns its width: on mid / cooked it grows to ring + badge ("CPU 96%") and shrinks back on
  recovery, unless the culprit's own item is already shown (built 2026-11-18, not seen on screen). Still ⬜:
  ring-only as the default for new installs.
- ⬜ Keep-awake cup as a badge in the ring's gap instead of a second item (standalone cup stays an option).
- ⬜ Auto-collapse to the combined item when macOS actually hides a separate item behind the notch, with a
  one-time plain notice.
- 🟡 Hover tooltip with the verdict sentence; accessibility label reads the verdict, not "CPU 96" (built
  2026-11-18 for the ring and combined items; not seen on screen).
- ⬜ ⌥-click toggles keep awake; drop a file / folder on the ring to stay awake until it finishes, drop an
  app to stay awake while it runs.

**Features that reuse what VibeCheck already knows**
- ✅ **Agent watch** (2026-11-18; notification not seen on screen): keep-awake trigger "While an AI agent is working" (from `isWorking` in
  `AgentUsageMonitor`) and an opt-in "Agent finished" notification after a long run.
- ⬜ **Call guard:** camera / mic in use (`kCMIODevicePropertyDeviceIsRunningSomewhere`,
  `kAudioDevicePropertyDeviceIsRunningSomewhere`) holds non-critical alerts, keeps the display awake and
  warns before a call stutters, with the usual Quit rules. Focus filter (`SetFocusFilterIntent`) to choose
  per Focus.
- ⬜ **Vibe replay:** record each mid / cooked episode with culprit and duration; a 24 h vibe strip and a
  repeat-offender line ("Chrome Helper cooked your Mac 4 times this week, 52 min total").

**Layout and motion**
- ⬜ Six tiles by default (CPU, Memory, Network, Sensors, Battery, Agents); Clock and Weather off for new
  installs, Empty Trash moves from the toggles to ⌘K. Tiles never reorder by severity.
- ⬜ Discoverability: the cup's tooltip names the hold gesture; one dismissible hint line after an update.
- ⬜ Settings audit: anything a user wouldn't change in the first week goes under "Advanced".
- ⬜ **Recovery check:** cooked / mid → vibing draws the brand's pulse-to-check through the ring's gap once
  (trim 0 → 1, spring 0.5 / 0.75). Reduce Motion: 150 ms crossfade. Never on launch.
- ⬜ **Culprit drain:** after quitting the culprit, its number rolls down, the outline drains (trim
  reversing, 400 ms) and the header ring refills.
- ⬜ Drop target: the ring dilates 10% while something is dragged over it.
- ⬜ Custom SF Symbol for the menu bar ring (variable value, template rendering).

Haptics only fire while a finger is on a Force Touch trackpad: use them for direct manipulation (dial
detents, chart peaks), never for background events.
