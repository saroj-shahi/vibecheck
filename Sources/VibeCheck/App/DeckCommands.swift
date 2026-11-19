import AppKit

/// One action in the deck's ⌘K command palette.
struct DeckCommand: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var shortcut: String?
    /// Extra words that should find this command ("caffeinate" → keep awake).
    var keywords = ""
    /// Needs a second ↩ (or click) before it runs: things that can't be undone with one more keystroke.
    var confirm = false
    /// The Settings pane that goes with this command, offered in its ⌘↩ actions.
    var settingsSection: SettingsSection?
    let run: @MainActor () -> Void
}

/// Every action the palette offers, and how typing filters them.
@MainActor
enum DeckCommands {
    /// Most results shown at once; the deck must stay small.
    nonisolated static let limit = 8

    /// Where the palette gets the processes it offers to quit (set by the deck; nil means none are offered).
    static weak var stats: SystemStats?

    /// Apps offered as "Quit X" / "Force Quit X".
    nonisolated static let processCommandCount = 3

    static func all(model: DeckModel, settings: AppSettings) -> [DeckCommand] {
        var list: [DeckCommand] = []
        let close = { model.requestClose?() }

        for module in model.modules {
            list.append(DeckCommand(id: "module.\(module.rawValue)", title: String(localized: "Open \(module.title)"), symbol: module.symbol,
                                    shortcut: module.shortcutKey.map { "⌘\($0)" }, keywords: "show view details",
                                    settingsSection: .module(module)) {
                model.closePalette()
                model.go(.module(module))
            })
        }

        // One row whose title follows the state, so rows never appear or vanish under the selection.
        let awake = KeepAwake.shared
        let length = settings.keepAwake.defaultMinutes
        list.append(DeckCommand(id: "awake.toggle",
                                title: awake.isActive ? String(localized: "Stop keeping awake")
                                    : length == 0 ? String(localized: "Keep awake") : String(localized: "Keep awake for \(AwakePreset.title(length))"),
                                symbol: awake.isActive ? "cup.and.saucer" : "cup.and.saucer.fill",
                                keywords: "caffeinate sleep stop", settingsSection: .keepAwake) {
            if awake.isActive { awake.stop() } else { awake.start(minutes: length) }
            model.closePalette()
        })
        if length != 0 {
            list.append(DeckCommand(id: "awake.forever", title: String(localized: "Keep awake until stopped"), symbol: "infinity",
                                    keywords: "caffeinate sleep indefinitely", settingsSection: .keepAwake) { awake.start(minutes: 0); model.closePalette() })
        }
        for minutes in FocusPreset.minutes {
            list.append(DeckCommand(id: "focus.\(minutes)", title: String(localized: "Focus for \(minutes) minutes"), symbol: "timer",
                                    keywords: "pomodoro timer session", settingsSection: .keepAwake) { awake.startFocus(minutes: minutes); model.closePalette() })
        }

        let quick = QuickActions.shared
        list.append(DeckCommand(id: "toggle.dark", title: quick.isDark ? String(localized: "Switch to light mode") : String(localized: "Switch to dark mode"),
                                symbol: quick.isDark ? "sun.max" : "moon.fill", keywords: "appearance theme dark light") {
            quick.toggleDarkMode(); model.closePalette()
        })
        list.append(DeckCommand(id: "toggle.mic", title: quick.isMicMuted ? String(localized: "Unmute the microphone") : String(localized: "Mute the microphone"),
                                symbol: quick.isMicMuted ? "mic.fill" : "mic.slash.fill", keywords: "microphone audio mute") {
            quick.toggleMic(); model.closePalette()
        })

        list.append(DeckCommand(id: "trash.empty", title: String(localized: "Empty Trash"), symbol: "trash",
                                keywords: "bin delete clean", confirm: true) {
            if (quick.trashCount ?? 0) > 0 { quick.emptyTrash() }
            model.closePalette()
        })

        for rule in settings.alertRules {
            let describe = "\(rule.metric.title) \(rule.comparison.label) \(Int(rule.threshold))\(rule.metric.unit)"
            list.append(DeckCommand(id: "alert.\(rule.id.uuidString)",
                                    title: rule.enabled ? String(localized: "Turn off alert: \(describe)") : String(localized: "Turn on alert: \(describe)"),
                                    symbol: rule.enabled ? "bell.slash" : "bell", keywords: "alerts notify snooze mute pause",
                                    settingsSection: .alerts) {
                if let index = settings.alertRules.firstIndex(where: { $0.id == rule.id }) {
                    settings.alertRules[index].enabled.toggle()
                }
                model.closePalette()
            })
        }

        list.append(contentsOf: processCommands(stats: stats, model: model))

        for section in SettingsSection.allCases {
            list.append(DeckCommand(id: "settings.\(section.id)", title: String(localized: "\(section.title) settings"),
                                    symbol: section.symbol, keywords: "preferences settings options") {
                close()
                (NSApp.delegate as? AppDelegate)?.showSettings(section)
            })
        }
        list.append(DeckCommand(id: "quit", title: String(localized: "Quit VibeCheck"), symbol: "power", keywords: "exit close", confirm: true) {
            NSApp.terminate(nil)
        })
        return list
    }

    /// "Quit X" and "Force Quit X" for the busiest apps VibeCheck already samples. Both ask for a second
    /// step; the signal goes through `ProcessKiller`, which re-checks the protected list and start time.
    static func processCommands(stats: SystemStats?, model: DeckModel) -> [DeckCommand] {
        guard let stats else { return [] }
        var list: [DeckCommand] = []
        for app in stats.topApps(by: \.cpu, limit: processCommandCount) {
            let pid = app.id
            let name = app.name
            guard ProcessKiller.protectionReason(pid: pid) == nil, let target = ProcessKiller.identity(of: pid) else { continue }
            for (mode, verb) in [(ProcessKiller.Mode.quit, String(localized: "Quit")), (.forceQuit, String(localized: "Force Quit"))] {
                list.append(DeckCommand(id: "process.\(mode == .quit ? "quit" : "force").\(pid)", title: String(localized: "\(verb) \(name)"),
                                        symbol: mode == .quit ? "xmark.circle" : "xmark.octagon",
                                        keywords: "kill stop close process app", confirm: true) {
                    // Same name as when the row was listed, so a recycled pid is never signalled.
                    if ProcessKiller.name(of: pid) == name || ProcessKiller.identity(of: pid) == target {
                        ProcessKiller.quit(target, mode: mode)
                    }
                    model.closePalette()
                })
            }
        }
        return list
    }

    /// The ⌘↩ list for a row: run it, and open the Settings pane that goes with it (when there is one).
    static func actions(for command: DeckCommand, model: DeckModel) -> [DeckCommand] {
        var list = [DeckCommand(id: "action.run", title: command.confirm ? command.title : String(localized: "Run"), symbol: "return") {
            activate(command, model: model)
        }]
        if let section = command.settingsSection {
            list.append(DeckCommand(id: "action.settings", title: String(localized: "Open \(section.title) settings"), symbol: section.symbol) {
                model.requestClose?()
                (NSApp.delegate as? AppDelegate)?.showSettings(section)
            })
        }
        return list
    }

    /// Runs a command, or arms it first if it needs confirming (the row then asks for a second ↩).
    static func activate(_ command: DeckCommand, model: DeckModel) {
        if command.confirm && model.paletteConfirmID != command.id {
            model.paletteConfirmID = command.id
        } else {
            model.paletteConfirmID = nil
            // Process ids carry a pid, which gets reused: don't rank them.
            if !command.id.hasPrefix("process.") { RecentCommands.record(command.id) }
            command.run()
        }
    }

    /// Commands matching `query`, best first. Ties (and the empty query) put recently run commands first,
    /// then the original order.
    nonisolated static func filter(_ commands: [DeckCommand], query: String,
                                   recent: [String] = RecentCommands.load()) -> [DeckCommand] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        func rank(_ id: String) -> Int { recent.firstIndex(of: id) ?? Int.max }
        let scored: [(Int, Int, DeckCommand)] = commands.enumerated().compactMap { index, command in
            let value = q.isEmpty ? Optional(0) : score(q, title: command.title, keywords: command.keywords)
            return value.map { ($0, index, command) }
        }
        return scored
            .sorted {
                if $0.0 != $1.0 { return $0.0 > $1.0 }
                let (a, b) = (rank($0.2.id), rank($1.2.id))
                return a != b ? a < b : $0.1 < $1.1
            }
            .prefix(limit)
            .map(\.2)
    }

    /// How well a lowercased query matches; nil for no match. Pure, for tests.
    nonisolated static func score(_ query: String, title: String, keywords: String) -> Int? {
        let t = title.lowercased()
        if t.hasPrefix(query) { return 400 }
        let words = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(query) }) { return 300 }
        if t.contains(query) { return 200 }
        if keywords.lowercased().split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 150 }
        // Letters in order ("kpa" → "keep awake"), but only from word starts to avoid noise.
        let initials = String(words.compactMap(\.first))
        if isSubsequence(query, of: initials) { return 100 }
        return nil
    }

    nonisolated private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var it = haystack.makeIterator()
        return needle.allSatisfy { c in
            while let h = it.next() { if h == c { return true } }
            return false
        }
    }
}
