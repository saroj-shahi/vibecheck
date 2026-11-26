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
    /// More ⌘↩ actions after Run (clipboard rows: pin, delete).
    var extraActions: [DeckCommand] = []
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

        // Inline date & time calculator ("3pm EST", "today + 45d", "days until Dec 31").
        if let query = model.paletteQuery, let calc = TimeCalculator.evaluate(query) {
            list.append(DeckCommand(id: "timecalc", title: calc.title, symbol: "calendar.badge.clock",
                                    shortcut: String(localized: "Copy"),
                                    keywords: query, settingsSection: .module(.clock)) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(calc.copyValue, forType: .string)
                model.closePalette()
                model.showNotice(String(localized: "Copied: \(calc.copyValue)"))
            })
        }

        for module in model.modules {
            list.append(DeckCommand(id: "module.\(module.rawValue)", title: String(localized: "Open \(module.title)"), symbol: module.symbol,
                                    shortcut: module.shortcutKey.map { "⌘\($0)" }, keywords: "show view details",
                                    settingsSection: .module(module)) {
                model.closePalette()
                model.go(.module(module))
            })
        }

        // Calendar & Video Call quick actions
        if settings.clock.showCalendarEvents, CalendarStore.shared.access == .granted {
            let joinable = CalendarLogic.nextJoinableCall(in: CalendarStore.shared.events, now: Date(),
                                                          hiddenCalendarIDs: settings.clock.hiddenCalendarIDs)
            list.append(DeckCommand(id: "calendar.joinCall",
                                    title: joinable.map { String(localized: "Join \($0.title)") } ?? String(localized: "Join video call"),
                                    symbol: "video.fill",
                                    keywords: "meeting call zoom meet teams webex facetime join video calendar",
                                    settingsSection: .module(.clock)) {
                close()
                if CalendarStore.shared.joinNextVideoCall() == nil {
                    model.showNotice(String(localized: "No video call starting soon."))
                }
            })
        }
        list.append(DeckCommand(id: "calendar.open", title: String(localized: "Open Calendar"), symbol: "calendar",
                                keywords: "calendar schedule events date apple calendar",
                                settingsSection: .module(.clock)) {
            close()
            CalendarDateHelper.openCalendarApp()
        })

        // To-do on: opens its panel with the "Add task" field focused (the panel asks for Reminders access if needed).
        if model.modules.contains(.todo) {
            list.append(DeckCommand(id: "todo.add", title: String(localized: "Add task…"), symbol: "plus.circle",
                                    keywords: "todo to-do reminder reminders task new checklist",
                                    settingsSection: .module(.todo)) {
                RemindersStore.shared.wantsAddFocus = true
                model.go(.module(.todo))
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

        if settings.onDeviceExplanations, OnDeviceExplainer.availability() == .available {
            list.append(DeckCommand(id: "explain.mac", title: String(localized: "Explain my Mac"), symbol: "sparkles",
                                    keywords: "why slow vibe explain apple intelligence what is wrong") {
                model.go(.home)
                model.closePalette()
                ExplainCard.shared.start(stats: stats)
            })
        }
        list.append(contentsOf: processCommands(stats: stats, model: model))
        list.append(DeckCommand(id: "cursor.find", title: String(localized: "Find my cursor"), symbol: "cursorarrow.rays",
                                keywords: "mouse pointer locate where highlight", settingsSection: .shortcuts) {
            close()
            CursorFinder.flash()
        })
        list.append(DeckCommand(id: "vibe.card", title: String(localized: "Share Vibe Card"), symbol: "square.and.arrow.up",
                                keywords: "export image png screenshot share vibe card copy save") {
            close()
            VibeCardWindow.show(stats: stats)
        })
        list.append(DeckCommand(id: "keyboard.clean", title: String(localized: "Clean keyboard"), symbol: "keyboard",
                                keywords: "wipe disable lock keys clean") {
            close()
            KeyboardCleaner.shared.start()
        })
        list.append(contentsOf: clipboardCommands(model: model))

        for section in SettingsSection.allCases {
            list.append(DeckCommand(id: "settings.\(section.id)", title: String(localized: "\(section.title) settings"),
                                    symbol: section.symbol, keywords: "preferences settings options") {
                close()
                (NSApp.delegate as? AppDelegate)?.showSettings(section)
            })
        }
        list.append(DeckCommand(id: "update.check", title: String(localized: "Check for Updates"), symbol: "arrow.down.circle",
                                keywords: "update upgrade version new release brew terminal", settingsSection: .about) {
            close()
            (NSApp.delegate as? AppDelegate)?.showSettings(.about)
            Task { await UpdateChecker.shared.check() }
        })
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

    /// Pinned snippets, then clipboard history (newest first), then "Clear clipboard history". Rows are found
    /// by their contents; typing "clip" shows only these (see `filter`).
    static func clipboardCommands(model: DeckModel) -> [DeckCommand] {
        let clip = ClipboardHistory.shared
        let keywords = "clip clipboard paste copied history"
        func paste(_ copy: () -> Void) {
            copy()
            if ClipboardHistory.pasteCopied() { model.requestClose?() } else { model.showNotice(String(localized: "Copied. Press ⌘V to paste.")) }
        }
        var list: [DeckCommand] = clip.snippets.enumerated().map { index, text in
            DeckCommand(id: "clip.snippet.\(index)", title: ClipItem.preview(text), symbol: "pin.fill",
                        keywords: "\(keywords) snippet pinned \(text.prefix(300))", settingsSection: .clipboard,
                        extraActions: [DeckCommand(id: "action.unpin", title: String(localized: "Unpin"), symbol: "pin.slash") {
                            clip.unpin(text)
                        }]) {
                model.closePalette()
                paste { clip.copy(snippet: text) }
            }
        }
        for item in clip.items {
            var actions: [DeckCommand] = []
            if case .files = item.content {
                actions.append(DeckCommand(id: "action.astext", title: String(localized: "Paste as plain text"), symbol: "text.alignleft") {
                    paste { clip.copy(item, asText: true) }
                })
            }
            if case .text(let text) = item.content {
                actions.append(DeckCommand(id: "action.pin", title: String(localized: "Pin"), symbol: "pin") { clip.pin(text) })
            }
            actions.append(DeckCommand(id: "action.delete", title: String(localized: "Delete from history"), symbol: "trash") { clip.delete(item) })
            let searchable = if case .text(let text) = item.content { String(text.prefix(300)) } else { item.title }
            list.append(DeckCommand(id: "clip.\(item.id.uuidString)", title: item.title, symbol: item.symbol,
                                    keywords: "\(keywords) \(item.appName ?? "") \(searchable)", settingsSection: .clipboard,
                                    extraActions: actions) {
                model.closePalette()
                paste { clip.copy(item) }
            })
        }
        if !clip.items.isEmpty {
            list.append(DeckCommand(id: "clip.clear", title: String(localized: "Clear clipboard history"), symbol: "clear",
                                    keywords: keywords, confirm: true, settingsSection: .clipboard) {
                clip.clear()
                model.closePalette()
            })
        }
        return list
    }

    /// The ⌘↩ list for a row: run it, and open the Settings pane that goes with it (when there is one).
    static func actions(for command: DeckCommand, model: DeckModel) -> [DeckCommand] {
        var list = [DeckCommand(id: "action.run", title: command.confirm ? command.title
                                    : command.id.hasPrefix("clip.") ? String(localized: "Paste") : String(localized: "Run"), symbol: "return") {
            activate(command, model: model)
        }]
        list.append(contentsOf: command.extraActions)
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
            // Process ids carry a pid, which gets reused, and clipboard/calculator rows come and go: don't rank them.
            if !command.id.hasPrefix("process.") && !command.id.hasPrefix("clip.") && command.id != "timecalc" {
                RecentCommands.record(command.id)
            }
            command.run()
        }
    }

    /// Commands matching `query`, best first. Ties (and the empty query) put recently run commands first,
    /// then the original order.
    nonisolated static func filter(_ commands: [DeckCommand], query: String,
                                   recent: [String] = RecentCommands.load()) -> [DeckCommand] {
        var q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var commands = commands
        // "clip" (or "clip …") narrows to the clipboard rows and searches them with the rest.
        if q == "clip" || q.hasPrefix("clip ") {
            commands = commands.filter { $0.id.hasPrefix("clip.") }
            q = String(q.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }
        func rank(_ id: String) -> Int { recent.firstIndex(of: id) ?? Int.max }
        let scored: [(Int, Int, DeckCommand)] = commands.enumerated().compactMap { index, command in
            if command.id == "timecalc" { return (1000, index, command) }
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
