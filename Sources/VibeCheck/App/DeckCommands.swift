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

    static func all(model: DeckModel, settings: AppSettings) -> [DeckCommand] {
        var list: [DeckCommand] = []
        let close = { model.requestClose?() }

        for module in model.modules {
            list.append(DeckCommand(id: "module.\(module.rawValue)", title: "Open \(module.title)", symbol: module.symbol,
                                    shortcut: module.shortcutKey.map { "⌘\($0)" }, keywords: "show view details",
                                    settingsSection: .module(module)) {
                model.closePalette()
                model.go(.module(module))
            })
        }

        // One row whose title follows the state, so rows never appear or vanish under the selection.
        let awake = KeepAwake.shared
        let length = settings.keepAwakeDefaultMinutes
        list.append(DeckCommand(id: "awake.toggle",
                                title: awake.isActive ? "Stop keeping awake"
                                    : length == 0 ? "Keep awake" : "Keep awake for \(AwakePreset.title(length))",
                                symbol: awake.isActive ? "cup.and.saucer" : "cup.and.saucer.fill",
                                keywords: "caffeinate sleep stop", settingsSection: .keepAwake) {
            if awake.isActive { awake.stop() } else { awake.start(minutes: length) }
            model.closePalette()
        })
        if length != 0 {
            list.append(DeckCommand(id: "awake.forever", title: "Keep awake until stopped", symbol: "infinity",
                                    keywords: "caffeinate sleep indefinitely", settingsSection: .keepAwake) { awake.start(minutes: 0); model.closePalette() })
        }
        for minutes in FocusPreset.minutes {
            list.append(DeckCommand(id: "focus.\(minutes)", title: "Focus for \(minutes) minutes", symbol: "timer",
                                    keywords: "pomodoro timer session", settingsSection: .keepAwake) { awake.startFocus(minutes: minutes); model.closePalette() })
        }

        let quick = QuickActions.shared
        list.append(DeckCommand(id: "toggle.dark", title: quick.isDark ? "Switch to light mode" : "Switch to dark mode",
                                symbol: quick.isDark ? "sun.max" : "moon.fill", keywords: "appearance theme dark light") {
            quick.toggleDarkMode(); model.closePalette()
        })
        list.append(DeckCommand(id: "toggle.mic", title: quick.isMicMuted ? "Unmute the microphone" : "Mute the microphone",
                                symbol: quick.isMicMuted ? "mic.fill" : "mic.slash.fill", keywords: "microphone audio mute") {
            quick.toggleMic(); model.closePalette()
        })

        for section in SettingsSection.allCases {
            list.append(DeckCommand(id: "settings.\(section.id)", title: "\(section.title) settings",
                                    symbol: section.symbol, keywords: "preferences settings options") {
                close()
                (NSApp.delegate as? AppDelegate)?.showSettings(section)
            })
        }
        list.append(DeckCommand(id: "quit", title: "Quit VibeCheck", symbol: "power", keywords: "exit close", confirm: true) {
            NSApp.terminate(nil)
        })
        return list
    }

    /// The ⌘↩ list for a row: run it, and open the Settings pane that goes with it (when there is one).
    static func actions(for command: DeckCommand, model: DeckModel) -> [DeckCommand] {
        var list = [DeckCommand(id: "action.run", title: command.confirm ? command.title : "Run", symbol: "return") {
            activate(command, model: model)
        }]
        if let section = command.settingsSection {
            list.append(DeckCommand(id: "action.settings", title: "Open \(section.title) settings", symbol: section.symbol) {
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
            command.run()
        }
    }

    /// Commands matching `query`, best first; the original order breaks ties (and is the order for "").
    nonisolated static func filter(_ commands: [DeckCommand], query: String) -> [DeckCommand] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Array(commands.prefix(limit)) }
        return commands.enumerated()
            .compactMap { index, command in score(q, title: command.title, keywords: command.keywords).map { ($0, index, command) } }
            .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
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
