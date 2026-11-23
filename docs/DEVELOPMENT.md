# Developing VibeCheck

How VibeCheck is built and why: the design rules, the decisions behind them, and notes for working on the
code. What's planned next is in [ROADMAP.md](ROADMAP.md); which file does what is in [CODEMAP.md](CODEMAP.md);
brand, voice and motion are in [BRAND.md](../branding/BRAND.md), which wins over this file on those.

## Design rules

Condensed from three reviews: the "menu bar Creative Director" brief (round one), a popover
mockup review (round two) and the Apple Design Award style
teardown (round three). BRAND.md still decides voice, color and motion.

**The idea.** A verdict first and a cockpit second, in a 390 pt sheet of glass. Everything folds behind three
doors: **tile → detail**, **cup → menu**, **⌘K → anything**. Before adding UI, ask whether it can be a palette
command.

**What the ADA teardown said (round three).** Award-grade: the verdict-first idea, the single non-activating
deck, the drawn ⌘K field, the culprit outline. Holding it back: too many jobs at once (Empty Trash, Clock
and Weather fail the menu bar test), separate items a notched MacBook will evict, idle cost that scales with
item count, hidden gestures, unverified accessibility, no distribution. Call guard and vibe replay came from it.

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

**Benchmarks.** A launcher-style command bar (type anywhere, keyboard selection with the mouse still
working, shortcut hints on the right). Dense menu bar monitors for density (one number per tile, axis-less sparklines).
Left out on purpose: four-column toggle tiles, blue accent fills on active tiles, grouped
results while typing, its 12 pt radius and web fonts.

## Decisions

Choices that shouldn't be undone without a good reason.

| Decision | Why |
|---|---|
| Clipboard history reads the pasteboard only when `changeCount` changes, and stays off by default; Settings warns when macOS's "Paste from Other Apps" is Ask or Deny (spike, 2026-11-23, macOS 27.2.1) | `NSPasteboard.accessBehavior` (15.4+) defaults the general pasteboard to "ask on programmatic access" for apps never allowed; `changeCount` and `types` are metadata. So history works, but a Mac set to Ask prompts on reads until the user picks Always Allow; that's the user's call, not ours |
| ⌘K "clip" (or "clip …") narrows the palette to clipboard rows; the global shortcut opens the palette with that query | One palette, no second UI; the filter is a query prefix, so it's testable and typed the same way |
| Clipboard: text and file items can persist (`clipboard.json`, 0600); images stay in memory; history and "keep across restarts" are per Mac, not in settings backup; snippets are in backup | Recording and writing copies to disk are privacy decisions per machine; snippets are typed or pinned on purpose. Images up to 5 MB each would make every save heavy |
| Clipboard paste posts ⌘V only with Accessibility and only if the same app is still frontmost 0.15 s later; otherwise it copies and says "press ⌘V" | Never paste into an app the user didn't pick (e.g. a password field that came forward) |
| Keyboard cleaning swallows keys through a session `CGEventTap` with a 45 s wall-clock deadline (not tick counting), re-enabled after macOS timeouts, stopped on quit | The tap must never outlive its promise, even across sleep or a stalled main thread |
| Clipboard (modifier + V) and find-my-cursor (modifier + F) global shortcuts are off by default | With the ⌥⌘ modifier they'd steal Finder's "Move here" and many apps' Find/Replace |
| The star / support prompt shows exactly once, 2 days after first launch, and is marked shown before it opens (owner, 2026-11-20) | Asking for support must never become a nag; existing installs count from the first launch of the version that added it |
| Keep awake on state loops (steam shimmer) though motion otherwise never decorates (2026-11-19) | Owner found the old filled-cup state "not fun"; the loop only runs while the deck is open and stops with Reduce Motion |
| Mouse, keyboard and clipboard back on the roadmap (2026-11-19, owner): clipboard history in ⌘K and pinned snippets (P1); find my cursor and keyboard cleaning mode (P2). History is off by default and never records concealed / transient items or anything copied during Secure Input | Owner asked for them. Kept to ⌘K commands and the fewest permissions, per the product rules; no input monitoring |
| Deck 390 pt (was 360), notifications popover 346 pt, ⌘↩ actions card 270 pt, alerts widened to 288 pt with an empty accessory view (2026-11-19) | Owner asked for wider pop-ups (~20% was too much; settled ~8% over the old sizes). 390 keeps tiles whole-pixel (114 pt) |
| Share with colleagues through an un-notarized `--share` DMG signed with Apple Development, not a paid Developer ID | The owner wants to share, not sell; each person runs one `xattr -dr com.apple.quarantine` command (a colleague found Open Anyway didn't work on their Mac, 2026-11-19; Terminal did). Building from source would need Xcode and repo access and loses the widget (team-signed app group) |
| Updates via the GitHub Releases API (`releases/latest`, tag `v<version>`), not Sparkle; the app shows the update command (`brew upgrade --cask vibecheck` or the install line), it doesn't replace itself (2026-11-19: was "opens the DMG") | No framework to embed with SwiftPM, no EdDSA keys; enough for a small app. Revisit Sparkle if silent in-place updates are wanted |
| Open source under GPL-3.0-or-later, with DCO sign-off and no CLA; name, icon and artwork kept out of the license (`TRADEMARKS.md`) (2026-11-19, owner) | GPL lets anyone use and fork but blocks closed-source clones; the trademark notice makes forks rename. Without a CLA the license can't be changed later for others' contributions |
| Public installs are Terminal-only: Homebrew tap (`saroj-shahi/tap`, `postflight` clears quarantine) and `scripts/install.sh` via curl, both fetching a `VibeCheck.zip` release asset; no DMG download (2026-11-19, owner) | Free path without the $99 Developer ID: curl downloads aren't quarantined, so the un-notarized app opens with no Gatekeeper block and no `xattr` step. The official homebrew/cask won't take apps that fail Gatekeeper, hence a tap |
| Hardened runtime only for Developer ID builds (or `VIBECHECK_HARDENED=1`), not the owner's daily Apple Development builds | Notarization needs it; keeps local builds as they were |
| The flat brand mark is the Mood Dial (ring, notched knob, check in the gap), not the old pulse-to-check | The owner asked for the mark to follow the app icon so the lockup, README and icon tell one story |
| Widgets without an Xcode project: SwiftPM builds the extension executable (linked with `-e _NSExtensionMain`), `build.sh` wraps and signs the `.appex` | Keeps the "no Xcode project" decision; without that entry point the extension traps on load |
| Team-prefixed app group (`77HKFF78Z8.io.github.saroj-shahi.vibecheck`), main app stays unsandboxed | Works without a provisioning profile; only the widget is sandboxed, as WidgetKit requires |
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
| Slang only for vibing / mid / cooked; alerts and errors stay plain | Brand voice (see BRAND.md ) |
| Bluetooth sleep: never touch Bluetooth at shutdown; only re-enable what VibeCheck turned off | A Mac shouldn't boot with Bluetooth off, and a user's own "off" must stick |
| Every IOBluetooth power call is guarded by `CBManager.authorization == .allowedAlways` | Without Bluetooth permission macOS aborts the process (TCC); the prompt is shown when the toggle is switched on, never at sleep |
| Quit actions hold the pid's start time and refuse if it changed | pids are reused; a stale menu must never signal a different process |
| Secure input warning says where macOS "points", not who holds it | `kCGSSessionSecureInputPID` records the frontmost app when secure input starts (a CLI tool's was reported as Chrome, then Slack) |
| Live Claude limits come from the user's own `claude` CLI (`get_usage` control request), never the Keychain or an Anthropic endpoint directly; opt-in, not in settings backup | Claude Code signs in and refreshes itself, so no Keychain prompts and no undocumented API |
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
| Turning an item off hides it (`isVisible = false`) instead of removing it; it's only removed on a reorder or a menu bar style change | `removeStatusItem` makes macOS forget where the user dragged the item among other apps' items; a hidden item keeps its spot and comes back there |
| Limit lists key on `RateWindow.key` (length + name) | Copilot's two monthly quotas share a length; keying on length drew one twice |
| Agents module: no network of its own; live Claude limits run the local `claude` CLI | Keeps "local logs only" true for VibeCheck itself |
| No cost estimates in the Agents module (owner, 2026-11-18) | It would need downloading a price list; never hard-code prices either |
| Settings: one sidebar page per module; the Menu Bar page keeps only order, on/off and display, and › opens the module page. Monitors list in fixed order, not the menu bar order | Options live in one place; a sidebar that reshuffles on reorder is hard to scan |
| Settings item rows reorder with `.onDrag` + a `DropDelegate` (insertion line, dimmed source row), not `.onMove` | `.onMove` does nothing in a macOS grouped `Form` (it needs a real `List`); `.dropDestination` only says "over this row", too vague to show where the item lands |
| Settings footers use `settingsFooter()` (caption, leading) | Grouped `Form` footers align trailing by default on macOS |
| Chart areas add points with `addLine`, never `addLines` | `addLines` starts a new subpath and breaks the closed fill |
| Agent watch counts an agent as working for 3 min after its last write (not the 2 min "working now" rule) | Long tool calls (tests, builds) write nothing for minutes; a shorter gap would end the session and notify mid-run |
| Agent logs are scanned while the Agents module, the agent keep-awake trigger or the "is done" notification is on | The features work with the Agents item hidden; still local files only |
| The ring's badge is skipped when the culprit's module has its own item; the ring re-measures only when the badge's shape (digit count) changes | Says nothing twice; neighbours don't shift as values change |
| Ring and combined items' accessibility labels end with the verdict (`qa item` matches by prefix) | VoiceOver and hover give the answer without opening the deck |

## Working on the project

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

- Settings live in the `io.github.saroj-shahi.vibecheck` defaults domain; history in
  `~/Library/Application Support/VibeCheck/history.json`.
- Conventional commit messages, signed off (`git commit -s`, see [CONTRIBUTING](../CONTRIBUTING.md)).
- Repo: `saroj-shahi/vibecheck` (public, GPL-3.0).
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
