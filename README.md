<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="branding/png/lockup-dark.png">
    <img src="branding/png/lockup-light.png" alt="VibeCheck" width="460">
  </picture>
</p>

<p align="center"><b>Is your Mac vibing or cooked?</b><br>
A native menu bar system monitor for macOS 14+, written in Swift with SwiftUI and AppKit.</p>

<p align="center">
  <a href="https://github.com/saroj-shahi/vibecheck/releases/latest/download/VibeCheck.dmg">
    <img src="https://img.shields.io/badge/Download_for_macOS-VibeCheck.dmg-3DE0B5?style=for-the-badge&logo=apple&logoColor=F5F7FF&labelColor=141833" alt="Download VibeCheck for macOS (latest release)" height="44">
  </a>
  <br>
  <sub>Always the latest release · macOS 14 Sonoma or later ·
  <a href="https://github.com/saroj-shahi/vibecheck/releases/latest">release notes</a></sub>
</p>

<p align="center"><img src="branding/png/social-card.png" alt="VibeCheck: CPU, GPU, memory, network, sensors and more" width="720"></p>

---

## Contents

- [Install](#install)
- [Getting started](#getting-started)
- [How to use each feature](#how-to-use-each-feature)
  - [The vibe ring](#the-vibe-ring) · [The deck](#the-deck) · [Command palette (⌘K)](#command-palette-k) ·
    [Modules](#modules) · [Keep awake](#keep-awake) · [Alerts and notifications](#alerts-and-notifications) ·
    [Call guard and Focus](#call-guard-and-focus) · [AI agents](#ai-agents) · [Desktop widgets](#desktop-widgets) ·
    [Shortcuts, Spotlight and Siri](#shortcuts-spotlight-and-siri) · [Settings](#settings) ·
    [Keyboard shortcuts](#keyboard-shortcuts) · [Updates](#updates)
- [Privacy](#privacy)
- [Develop](#develop) · [Brand](#brand) · [Roadmap](#roadmap)

## Install

1. **Download** [`VibeCheck.dmg`](https://github.com/saroj-shahi/vibecheck/releases/latest/download/VibeCheck.dmg)
   (the button above always gets the latest release).
2. **Open the DMG** and drag **VibeCheck** onto **Applications**.
3. **First launch only:** this build isn't notarized by Apple yet, so macOS blocks it until you clear the
   download flag. Run this once in Terminal (the DMG shows the same line):

   ```bash
   xattr -dr com.apple.quarantine /Applications/VibeCheck.app
   ```

4. **Open VibeCheck** from Applications. There's no Dock icon: look for the ring in your menu bar.
5. Optional: turn on **Launch at login** in Settings → General.

To uninstall, quit VibeCheck and move it to the Trash.

## Getting started

1. **Glance at the ring** in the menu bar. Full and monochrome means your Mac is vibing.
2. **Click it** to open the deck: one line telling you how your Mac is doing, and a live tile per stat.
3. **Click a tile** to see the detail and which apps are responsible.
4. **Press ⌘,** to pick what shows in the menu bar.

## How to use each feature

### The vibe ring

The ring sums up your Mac in one glance:

| Ring | State | Means |
|---|---|---|
| Full, monochrome | **Vibing** | All good |
| Two-thirds, yellow | **Mid** | Something is busy: sustained CPU, memory pressure, heat, low disk or battery |
| One-third, red | **Cooked** | Something needs you: thermal throttling, very high pressure, critical battery |

- **Hover** it for the verdict, e.g. _"Kinda mid: CPU has been busy at 72%."_ On mid or cooked a badge
  names the culprit beside it ("CPU 96%").
- **Click** to open the deck. **⌥-click** toggles keep awake.
- **Drop a file or folder** on it to stay awake until the file stops changing (handy for downloads and
  exports); **drop an app** to stay awake while that app runs.
- When things recover, a check sweeps through the ring's gap. States change only after two samples in a
  row, so nothing flickers.

### The deck

The glass panel that opens under the menu bar.

- **The verdict line** on top says what's going on and who is the loudest app.
- **Tiles** show each module live. Click one (or use the arrow keys and Return) and it unfolds into the
  module's detail view; **Esc** folds back, then closes. **⌘1…⌘9** jump between modules.
- **Detail views** lead with one big number and a summary, then a chart, then **who's responsible** (top
  apps), with everything else behind a remembered **Details** toggle. Hover a chart to scrub it, switch
  **Live / 1H / 24H**. History survives restarts; sleep shows as gaps.
- **Quit or force quit** a top app straight from its row (asks first). ⌘↩ runs a tile's main action.
- **The cup** is keep awake (see below); **the bell** lists the last 20 alerts, with a red dot for unseen
  ones; **the gear** opens Settings.
- **Quick toggles** for dark mode, mic mute and Empty Trash live in the deck and the palette.

### Command palette (⌘K)

Open the deck and press **⌘K**, or just start typing. Everything VibeCheck can do is a command: open a
module, start or stop keep awake, toggle dark mode or the mic, **Empty Trash** (press ↩ twice), **Quit /
Force Quit** one of the top 3 apps by CPU, turn an alert on or off, **Check for Updates**. The last 8
commands you ran come first.

### Modules

Turn each one on or off in Settings (new installs start with CPU, Memory, Network, Sensors, Battery and
Agents).

| Module | Menu bar | Detail view |
|---|---|---|
| CPU | mini history bars + % | user/system split, per-core bars, P/E cores, load average, thermal state, top apps, **vibe replay** (24 h vibe strip, "X cooked your Mac N times this week") |
| GPU | mini history bars + % | utilization, renderer/tiler split, GPU memory, model and cores |
| Memory | pressure-colored gauge + % | app/wired/compressed/cached breakdown, pressure, swap, top apps |
| Network | ↑/↓ rates, "Offline" when disconnected | per-interface traffic, Wi-Fi details, local IP (public IP opt-in), top apps by traffic, listening ports |
| Disk | read/write rates | I/O graph, every local volume with free space, connected USB devices |
| Sensors | hottest temperature | SoC, SSD and battery temperatures, fan speed, system and adapter power |
| Battery | icon + % | state, time left, power draw, health, cycles, 90-day charge and capacity history, Bluetooth device batteries |
| Weather | condition + temperature | now, next 12 hours, 7 days ([Open-Meteo](https://open-meteo.com/); pick a city, no location access) |
| Agents | agent logo + tokens today | see [AI agents](#ai-agents) |
| Clock | time | date, month calendar, world clocks with day/night and offset |

### Keep awake

Stops your Mac from idle-sleeping, like `caffeinate`.

- **Start it:** click the cup in the deck, ⌥-click the ring, press **⌃⌥⌘A** from any app, or use Shortcuts.
- **Choose how long:** drag around the cup's **hold dial** (15 min / 1 h / 4 h / ∞), or use the cup menu for
  a length, a time of day, or **while an app is running**.
- **Automatic triggers** (Settings → Keep Awake): while plugged in, while an external display is connected,
  while on a chosen Wi-Fi network (asks for Location only when you turn it on), on a schedule, while files
  are downloading, while an AI agent is working, or when VibeCheck opens.
- While it's on, a small cup sits inside the ring (or as its own menu bar item, if you prefer).
  Sessions stop on their own on low battery and send a notification when they end by themselves.

### Alerts and notifications

Rules read as sentences in Settings → Alerts: _Tell me when **CPU usage** is **above** **90%** for **1 min**._

- Click any bold word to change it; drag the number sideways to adjust it; preview the banner.
- Each module's page in Settings also lists that module's alerts.
- The deck's **bell** keeps the last 20 alerts and keep-awake endings with time and value.

### Call guard and Focus

On by default. When your camera or mic is in use, VibeCheck holds non-critical alerts until the call
ends (temperature and battery still come through), keeps the display awake, and warns once if an app is
burning 100%+ CPU, with a Quit button.

For more control per Focus, go to System Settings → Focus → pick a Focus → **Add Filter** → VibeCheck, and
choose "Hold alerts" and / or "Keep display awake".

### AI agents

The Agents module reads **local logs only** (nothing is sent anywhere) from Claude Code, Codex, Copilot CLI
and OpenCode:

- Tokens today, the last 24 h by hour, a 7-day chart, busiest projects and per-model split.
- Usage limits: Codex limits, and Claude's current 5-hour window (estimated, or live through your own
  `claude` CLI).
- **Several Claude accounts?** Pick which one in Settings → Agents (auto-found `~/.claude-*` folders, or
  "Choose account folder…").
- **Agent watch:** keep your Mac awake while an agent is working, and get an "<Agent> is done"
  notification after runs of 10 minutes or more.
- Switch agents you don't use off in Settings → Agents; they disappear everywhere.

### Desktop widgets

Right-click the desktop → **Edit Widgets** → search "VibeCheck":

- **Vibe** (small): the ring, the vibe word and the reason.
- **CPU and Memory** (medium): the ring, the verdict and last-hour sparklines.

Widgets update while VibeCheck runs and dim if it has been quit for a while.

### Shortcuts, Spotlight and Siri

The Shortcuts app gets **Get Mac Vibe**, **Get Mac Stat** (CPU, GPU, memory, free disk, download/upload
speed, hottest temperature, battery, agent tokens today), **Open VibeCheck Deck** (optionally on a module),
**Keep Mac Awake** (for N minutes or until stopped) and **Let Mac Sleep**. Several also work from Spotlight
and Siri, e.g. _"Keep my Mac awake with VibeCheck"_.

### Settings

Open with the gear in the deck, **⌘,**, or by opening the app again. A searchable sidebar groups the pages:

- **General:** update interval, launch at login, turn Bluetooth off while asleep (Advanced).
- **Menu Bar:** a live preview with your real stats. Choose **Just the vibe ring** (default), separate items
  or **one combined item**; spacing; colorful or single-color graphs; drag to reorder; per-item style (graph,
  icon or value). **Fit around the camera notch** shows only what fits beside the notch plus a "+N" badge.
- **One page per module:** on/off, how it looks in the menu bar, its alerts and its shortcut.
- **Keep Awake**, **Alerts**, **Agents**, **Clock** (formats, seconds, world clocks), **Weather** (city, °C / °F).
- **Shortcuts:** global hotkeys (see below).
- **Backup:** export, import or reset settings.
- **About:** version and the update check.

Less-used options sit under each page's **Advanced** section.

### Keyboard shortcuts

| Shortcut | Where | Does |
|---|---|---|
| `⌃⌥⌘1`…`⌃⌥⌘9`, `⌃⌥⌘0` | anywhere | open the deck on a module |
| `⌃⌥⌘A` | anywhere | toggle keep awake |
| `⌘K` or start typing | deck | command palette |
| `⌘1`…`⌘9` | deck | jump to a module |
| arrows, `↩` | deck | move between tiles, open one |
| `⌘↩` | deck | run the tile's action |
| `Esc` | deck | fold back, then close |
| `⌘,` | deck | Settings |

If another app is using secure input (a password field, some terminals), global shortcuts pause and the
deck says so.

### Updates

VibeCheck checks this repository's latest release at most once a day and sends one notification per new
version. Check now from Settings → About or ⌘K → "Check for Updates", or turn the check off there.

## Privacy

Everything is read on your Mac. VibeCheck has no account, no analytics and no server. The only network
calls are the weather (Open-Meteo, for the city you pick), the update check (GitHub), and the public IP
(api.ipify.org) only if you turn it on.

## Develop

```bash
./build.sh                  # builds build/VibeCheck.app (--install copies it to /Applications)
swift test                  # the unit tests: alerts, history, charts, layout, vibe score, notch fit, backup…
swift build && .build/debug/VibeCheck --dump    # print one sample from every monitor
build/VibeCheck.app/Contents/MacOS/VibeCheck --deck-demo   # open the deck and log its frames
/Applications/VibeCheck.app/Contents/MacOS/VibeCheck --login-item on   # launch at login (or off / status)
```

**Making a release:** `scripts/release.sh --share` builds `build/release/VibeCheck-<version>.dmg` with the
branded install window (signed, not notarized); `scripts/release.sh` makes the notarized one once a
Developer ID is set up (see the top of the script). Publish it with the steps the script prints: the release
must carry a `VibeCheck.dmg` asset, which is what the download button links to.

| Folder | What's inside |
|---|---|
| `Sources/VibeCheck/Monitors/` | Data collectors: Mach host stats, sysctl, IOKit, IOPowerSources, SMC, HID sensors, `ps`, `nettop` |
| `Sources/VibeCheck/App/` | `SystemStats`, settings, the deck controller, vibe score, alerts, history, weather, hotkeys |
| `Sources/VibeCheck/Views/` | Menu bar labels, deck, detail panels, charts, settings window |
| `branding/` | Brand guide, SVG sources, rendered PNGs and the DMG art |
| `scripts/` | `release.sh` (DMG), `render_brand.swift` (icon and brand assets), `render_dmg.swift` (install window art) |

See [`docs/CODEMAP.md`](docs/CODEMAP.md) for which file does what.

## Brand

<img src="branding/png/icon-256.png" alt="VibeCheck app icon" width="96" align="left">

The mark is a **mood dial**: the **vibe ring** as its track, a knob pointing at the ring's gap and a
**check** in that gap: your Mac, dialled to vibing. The palette runs **Mint → Sky → Violet** on deep **Ink** and **Night**;
the wordmark is SF Pro Rounded Bold with "Check" in the gradient. Voice: casual and honest, slang only for
**vibing, mid, cooked**.

<br clear="left">

<img src="branding/png/palette.png" alt="VibeCheck palette" width="100%">

The full guide (logo usage, clear space, color roles, type, voice, motion) is in
[`branding/BRAND.md`](branding/BRAND.md). All artwork is generated from SVG:

```bash
swift scripts/render_brand.swift   # rewrites branding/png/* and Resources/AppIcon.icns
```

## Roadmap

Features by priority, what has shipped, what's been verified, the design rules, known limits and the
decisions log live in [`docs/ROADMAP.md`](docs/ROADMAP.md).
