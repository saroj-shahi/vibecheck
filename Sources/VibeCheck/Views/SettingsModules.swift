import AppKit
import SwiftUI

// MARK: - One page per module

extension Module {
    /// Clock, Weather and To-do sit under "Extras" in the Settings sidebar; the rest are monitors.
    var isExtra: Bool { self == .clock || self == .weather || self == .todo }

    /// One line under the module's name at the top of its Settings page.
    var settingsSummary: String {
        switch self {
        case .cpu: String(localized: "How hard the processor is working, and which apps are pushing it.")
        case .gpu: String(localized: "Graphics load from games, video and machine learning.")
        case .memory: String(localized: "Memory in use, memory pressure and the apps holding the most.")
        case .network: String(localized: "Download and upload speed, the apps doing the talking and listening ports.")
        case .disk: String(localized: "Free space on the startup disk, and read and write speed.")
        case .sensors: String(localized: "Temperatures and fan speeds from the Mac's own sensors.")
        case .battery: String(localized: "Charge, time left and health, plus Bluetooth accessories and USB devices.")
        case .agents: String(localized: "Tokens and plan limits for Claude Code, Codex, Copilot, OpenCode and Antigravity.")
        case .clock: String(localized: "Menu bar clock, calendar events, meeting join links, alerts and world clocks.")
        case .weather: String(localized: "Today's forecast for one city, from Open-Meteo.")
        case .todo: String(localized: "A simple to-do list, kept in Apple Reminders.")
        }
    }

    /// Extra words the Settings search should match for this page.
    var settingsKeywords: String {
        switch self {
        case .cpu: "processor load cores usage"
        case .gpu: "graphics"
        case .memory: "ram pressure swap"
        case .network: "wifi download upload speed ports"
        case .disk: "storage ssd free space read write"
        case .sensors: "temperature heat fans celsius fahrenheit"
        case .battery: "charge power health cycles accessories bluetooth usb"
        case .agents: "ai claude codex copilot opencode antigravity agy tokens limits usage"
        case .clock: "time world time zone seconds calendar events meeting zoom meet teams video call chime"
        case .weather: "forecast city temperature units"
        case .todo: "todo to-do tasks reminders checklist list"
        }
    }
}

/// A module's own page: whether it's on, how it looks in the menu bar, its options, alerts and shortcut.
struct ModuleSettings: View {
    let module: Module
    @Environment(AppSettings.self) private var settings

    private var isOn: Bool { settings.isEnabled(module) }
    private var metrics: [AlertMetric] { AlertMetric.metrics(for: module) }

    var body: some View {
        Form {
            Section { hero }
            menuBarSection
            switch module {
            case .agents:
                AgentSourcesSection()
                ClaudeLimitsSection()
                AntigravityLimitsSection()
            case .network: PublicIPSection()
            case .clock: ClockSections()
            case .weather: WeatherSections()
            case .todo: TodoSections()
            default: EmptyView()
            }
            if !metrics.isEmpty { ModuleAlertsSection(module: module, metrics: metrics) }
            shortcutSection
        }
        .settingsForm()
    }

    private var hero: some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: module.symbol, color: module.accent, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(module.title).font(.title2.weight(.semibold))
                Text(module.settingsSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("Show \(module.title)", isOn: Binding(get: { isOn }, set: { settings.setEnabled(module, $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                // At least one module stays on.
                .disabled(isOn && settings.enabledModules.count == 1)
                .help(isOn ? "Turn \(module.title) off" : "Turn \(module.title) on")
        }
        .padding(.vertical, 6)
    }

    private var menuBarSection: some View {
        Section {
            LabeledContent("Preview") {
                MenuBarLabel(module: module, padded: true)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.bar))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
                    .accessibilityLabel("\(module.title) menu bar preview")
            }
            Picker("Display", selection: Binding(get: { settings.labelStyle(module) },
                                                 set: { settings.setLabelStyle($0, for: module) })) {
                ForEach(module.labelStyles) { Text($0.title(for: module)).tag($0) }
            }
            ModuleOptionRows(module: module)
        } header: {
            Text("Menu bar")
        } footer: {
            Text(isOn ? "Order and overall style are in Menu Bar." : "\(module.title) is off: it's hidden from the menu bar and the deck, and its shortcut just beeps.")
                .settingsFooter()
        }
        .disabled(!isOn)
    }

    private var shortcutSection: some View {
        AdvancedSection {
            LabeledContent("Open from anywhere") {
                Text(module.shortcutKey.map { "\(settings.hotkeyModifier.symbols)\($0)" } ?? "None")
                    .font(.body.monospaced())
                    .foregroundStyle(settings.hotkeysEnabled && isOn ? .primary : .tertiary)
            }
            LabeledContent("In the deck") {
                Text(module.shortcutKey.map { "⌘\($0)" } ?? "None")
                    .font(.body.monospaced())
                    .foregroundStyle(isOn ? .primary : .tertiary)
            }
            HStack(spacing: 4) {
                Text(settings.hotkeysEnabled ? "Press it again to close." : "Global shortcuts are off.")
                Button("Change in Shortcuts") { SettingsRouter.shared.open(.shortcuts) }
                    .buttonStyle(.link)
                    .foregroundStyle(Color.accentColor)
            }
            .settingsFooter()
        }
    }
}

/// The module's own menu bar options, as form rows.
private struct ModuleOptionRows: View {
    let module: Module
    @Environment(AppSettings.self) private var settings

    private var options: ItemOptions { settings.options(module) }

    private func binding<Value>(_ keyPath: WritableKeyPath<ItemOptions, Value>) -> Binding<Value> {
        Binding(get: { settings.options(module)[keyPath: keyPath] },
                set: { newValue in settings.updateOptions(module) { $0[keyPath: keyPath] = newValue } })
    }

    var body: some View {
        switch module {
        case .agents: agents
        case .memory: picker("Show", binding(\.memoryValue))
        case .network: picker("Show", binding(\.networkDirections))
        case .disk: picker("Show", binding(\.diskValue))
        case .battery: picker("Show", binding(\.batteryValue))
        case .sensors:
            Picker("Unit", selection: binding(\.sensorUnit)) {
                Text("°C").tag(TemperatureUnit.celsius)
                Text("°F").tag(TemperatureUnit.fahrenheit)
            }
            .pickerStyle(.segmented)
        case .clock:
            if settings.labelStyle(.clock) == .calendarIcon || settings.labelStyle(.clock) == .calendarIconOnly {
                Picker("Calendar icon", selection: Binding(get: { settings.clock.calendarIconStyle },
                                                           set: { settings.clock.calendarIconStyle = $0 })) {
                    ForEach(CalendarIconStyle.allCases) { Text($0.title).tag($0) }
                }
            }
        default: EmptyView()
        }
    }

    private func picker<Value: CaseIterable & Identifiable & Hashable>(_ title: String, _ selection: Binding<Value>) -> some View
    where Value.AllCases: RandomAccessCollection, Value: OptionTitled {
        Picker(title, selection: selection) {
            ForEach(Value.allCases) { Text($0.title).tag($0) }
        }
    }

    @ViewBuilder
    private var agents: some View {
        picker("Show", binding(\.agentValue))
        if options.agentValue.isLimits {
            picker("Limits", binding(\.agentWindows))
            Toggle("Show time until reset", isOn: binding(\.agentShowReset))
            if options.agentShowReset {
                Toggle("Show run-out time when close", isOn: binding(\.agentShowRunOut))
            }
        }
    }
}

/// Option enums with a user-facing title.
protocol OptionTitled { var title: String { get } }
extension ItemOptions.AgentValue: OptionTitled {}
extension ItemOptions.AgentWindows: OptionTitled {}
extension ItemOptions.MemoryValue: OptionTitled {}
extension ItemOptions.Directions: OptionTitled {}
extension ItemOptions.DiskValue: OptionTitled {}
extension ItemOptions.BatteryValue: OptionTitled {}

/// Only this module's alerts; edits go straight into the shared alert list.
private struct ModuleAlertsSection: View {
    let module: Module
    let metrics: [AlertMetric]
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let rules = settings.alertRules.filter { metrics.contains($0.metric) }
        Section {
            if rules.isEmpty {
                Text("No \(module.title) alerts.").foregroundStyle(.secondary)
            }
            ForEach(rules) { rule in
                AlertRuleRow(rule: binding(rule.id), metrics: metrics) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        settings.alertRules.removeAll { $0.id == rule.id }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        } header: {
            HStack {
                Text("Alerts")
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        settings.alertRules.insert(AlertRule.starter(for: metrics[0]), at: 0)
                    }
                } label: { Label("Add Alert", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
        } footer: {
            HStack(spacing: 4) {
                Text("Every alert, for all modules, is in")
                Button("Alerts") { SettingsRouter.shared.open(.alerts) }
                    .buttonStyle(.link)
                    .foregroundStyle(Color.accentColor)
            }
            .settingsFooter()
        }
    }

    /// By id rather than index, so deleting a row never leaves another row bound to a stale index.
    private func binding(_ id: AlertRule.ID) -> Binding<AlertRule> {
        Binding(get: { settings.alertRules.first { $0.id == id } ?? AlertRule.starter(for: metrics[0]) },
                set: { rule in
                    if let index = settings.alertRules.firstIndex(where: { $0.id == id }) { settings.alertRules[index] = rule }
                })
    }
}

/// Which agents the menu bar item counts (logo rows with switches) and which Claude Code account is read.
private struct AgentSourcesSection: View {
    @Environment(AppSettings.self) private var settings
    private let module = Module.agents

    private var options: ItemOptions { settings.options(module) }

    var body: some View {
        @Bindable var profiles = ClaudeProfiles.shared
        let sample = AgentUsageStore.shared.sample
        let found = sample.found
        Section {
            Text("Reads the usage Claude Code, Codex, OpenCode, GitHub Copilot and Antigravity record on this Mac, plus the plan limits Claude Code and Antigravity report when turned on. Prompts, replies and files are never kept, and your usage never leaves your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(AgentKind.allCases) { kind in
                HStack(spacing: 10) {
                    AgentLogoTile(agent: kind, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(kind.title)
                        Text(found.contains(kind) ? "Found on this Mac" : sample.scanned ? "Not found on this Mac" : "Looking…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Show \(kind.title)", isOn: Binding(
                        get: { options.includes(kind) },
                        set: { on in
                            settings.updateOptions(module) { $0.setAgent(kind, shown: on) }
                            AgentUsageStore.shared.refresh()
                        }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        // At least one agent stays on.
                        .disabled(options.includes(kind) && options.agents.count == 1)
                }
            }
            HStack(spacing: 10) {
                SettingsIcon(symbol: "person.crop.circle", color: .indigo, size: 26)
                Picker("Claude account", selection: $profiles.selectedID) {
                    ForEach(profiles.profiles) { Text($0.label).tag($0.id) }
                }
            }
            Button("Choose account folder…") { chooseFolder() }
        } header: {
            Text("Agents")
        } footer: {
            Text("Switched-off agents are left out of the menu bar; the deck still shows them all. For a second Claude Code account, pick its profile folder (the one CLAUDE_CONFIG_DIR points to, like ~/.claude-work): usage and live limits then come from that account. Claude Code itself isn't changed.")
                .settingsFooter()
        }
        .onAppear {
            profiles.refresh()
            AgentUsageStore.shared.refresh(fullWalk: true)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.message = String(localized: "Choose a Claude Code profile folder (the one CLAUDE_CONFIG_DIR points to).")
        panel.prompt = String(localized: "Use Folder")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !ClaudeProfiles.shared.add(url) {
            let alert = NSAlert()
            alert.messageText = String(localized: "That folder isn't a Claude Code profile")
            alert.informativeText = String(localized: "Choose a folder that has Claude Code's projects folder or .claude.json in it, like ~/.claude-work. Sign in to Claude Code with CLAUDE_CONFIG_DIR set to it first.")
            alert.widen()
            alert.runModal()
        }
    }
}

/// Opt-in live Claude limits (lives on the Agents page).
private struct ClaudeLimitsSection: View {
    var body: some View {
        @Bindable var claudeLimits = ClaudeLiveLimits.shared
        Section {
            Toggle("Show Claude's real plan limits", isOn: $claudeLimits.isOn)
            if claudeLimits.isOn {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(claudeLimits.statusText(now: context.date))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Claude Code")
        } footer: {
            Text(claudeLimits.isOn
                 ? String(localized: "Asks your Claude Code for your plan usage every 5 minutes, the same data /usage shows. No model request, no Keychain access; Claude Code signs in itself.")
                 : String(localized: "Off: Claude Code shows its local 5-hour estimate. When on, VibeCheck asks your Claude Code for your plan usage every 5 minutes, the same data /usage shows. No model request, no Keychain access."))
                .settingsFooter()
        }
    }
}

/// Opt-in live Antigravity limits via the user's `agy` CLI (lives on the Agents page).
private struct AntigravityLimitsSection: View {
    var body: some View {
        @Bindable var limits = AntigravityLiveLimits.shared
        Section {
            Toggle("Show Antigravity's real plan limits", isOn: $limits.isOn)
            if limits.isOn {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(limits.statusText(now: context.date))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Antigravity")
        } footer: {
            Text(limits.isOn
                 ? String(localized: "Asks your Antigravity CLI (agy) for your plan usage every 5 minutes, the same data /usage shows. No model request, no Keychain access; agy signs in itself.")
                 : String(localized: "Off: Antigravity shows its local 5-hour estimate. When on, VibeCheck asks your Antigravity CLI (agy) for your plan usage every 5 minutes, the same data /usage shows. No model request, no Keychain access."))
                .settingsFooter()
        }
    }
}

// MARK: - Clock

private struct ClockSections: View {
    @Environment(AppSettings.self) private var settings
    @State private var search = ""

    var body: some View {
        @Bindable var settings = settings
        Section {
            Picker("Format", selection: $settings.clock.format) {
                ForEach(ClockFormat.allCases) { format in
                    if format == .custom {
                        Text(format.title).tag(format)
                    } else {
                        Text(format.formatter(seconds: settings.clock.showSeconds).string(from: Date())).tag(format)
                    }
                }
            }
            if settings.clock.format == .custom {
                TextField("Custom pattern", text: $settings.clock.customFormat)
                    .font(.body.monospaced())
                LabeledContent("Result") {
                    Text(settings.clock.formatStyle.format(Date()))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if settings.clock.format != .custom {
                Toggle("Show seconds", isOn: $settings.clock.showSeconds)
            }
            Toggle("Show week number in menu bar", isOn: $settings.clock.showWeekNumberInMenuBar)
            Toggle("Show week numbers in calendar", isOn: $settings.clock.showWeekNumbersInCalendar)
            if settings.clock.panelHeight > 0 {
                LabeledContent("Custom popover height") {
                    HStack(spacing: 8) {
                        Text("\(Int(settings.clock.panelHeight)) pt").foregroundStyle(.secondary).monospacedDigit()
                        Button("Reset to Auto") { settings.clock.panelHeight = 0 }
                            .controlSize(.small)
                    }
                }
            }
        } header: {
            Text("Format & calendar")
        } footer: {
            if settings.clock.format == .custom {
                Text("Uses Unicode date tokens: EEE (Thu), d (26), MMM (Nov), MM (11), yyyy (2026), HH:mm (24h), h:mm a (12h), ss (seconds).").settingsFooter()
            }
        }

        Section {
            if settings.clock.worldClocks.isEmpty {
                Text("No world clocks yet.").foregroundStyle(.secondary)
            }
            ForEach($settings.clock.worldClocks) { $clock in
                HStack(spacing: 8) {
                    TextField("Name", text: $clock.name).labelsHidden().frame(maxWidth: 140)
                    Text(clock.timeZoneID).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text(clock.formattedTime(at: Date()))
                        .monospacedDigit().foregroundStyle(.secondary)
                    Button {
                        clock.showInMenuBar.toggle()
                    } label: {
                        Image(systemName: clock.showInMenuBar ? "pin.fill" : "pin")
                            .foregroundStyle(clock.showInMenuBar ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(clock.showInMenuBar ? "Shown in menu bar — click to unpin" : "Pin to menu bar beside local time")
                    Button(role: .destructive) {
                        settings.clock.worldClocks.removeAll { $0.id == clock.id }
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Remove \(clock.name)")
                }
            }
            TextField("Search city, country or time zone (e.g. San Francisco, IST, Tokyo)", text: $search)
            ForEach(matches) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name)
                        Text(entry.displaySubtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    let previewClock = WorldClock(name: entry.name, timeZoneID: entry.timeZoneID)
                    Text(previewClock.formattedTime(at: Date()))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Button("Add") {
                        settings.clock.worldClocks.append(WorldClock(name: entry.name, timeZoneID: entry.timeZoneID))
                        search = ""
                    }
                    .disabled(settings.clock.worldClocks.contains { $0.name == entry.name && $0.timeZoneID == entry.timeZoneID })
                }
            }
        } header: {
            Text("World clocks")
        } footer: {
            Text("Pin up to 3 world clocks to show compactly beside the local time in the menu bar. Search works completely offline.").settingsFooter()
        }

        CalendarEventsSettingsSection()
        NextEventSettingsSection()
        MeetingAlertsSettingsSection()
        HourlyChimeSettingsSection()
    }

    private var matches: [CityEntry] {
        CityIndex.search(search, limit: 8)
    }
}

private struct CalendarEventsSettingsSection: View {
    @Environment(AppSettings.self) private var settings
    private var store: CalendarStore { .shared }

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Show calendar events in Date & Time", isOn: $settings.clock.showCalendarEvents)
            if settings.clock.showCalendarEvents {
                switch store.access {
                case .granted:
                    Picker("Show upcoming", selection: $settings.clock.calendarDaysAhead) {
                        Text("Today only").tag(1)
                        Text("Next 3 days").tag(3)
                        Text("Next 7 days").tag(7)
                        Text("Next 14 days").tag(14)
                    }
                    Toggle("Show all-day events", isOn: $settings.clock.showAllDayEvents)
                    Toggle("Hide today's past events", isOn: $settings.clock.hidePastEventsToday)
                    Toggle("Include dated Apple Reminders", isOn: $settings.clock.showRemindersInAgenda)
                    if !store.calendars.isEmpty {
                        let allIDs = Set(store.calendars.map(\.id))
                        let selectedCount = store.calendars.count - settings.clock.hiddenCalendarIDs.intersection(allIDs).count
                        DisclosureGroup("Calendars (\(selectedCount) of \(store.calendars.count))") {
                            HStack(spacing: 10) {
                                Button("Select All") {
                                    settings.clock.hiddenCalendarIDs.removeAll()
                                }
                                .disabled(selectedCount == store.calendars.count)
                                Button("Deselect All") {
                                    settings.clock.hiddenCalendarIDs = allIDs
                                }
                                .disabled(selectedCount == 0)
                                Spacer()
                            }
                            .controlSize(.small)
                            .padding(.vertical, 2)

                            ForEach(store.calendars) { cal in
                                let enabled = !settings.clock.hiddenCalendarIDs.contains(cal.id)
                                Toggle(isOn: Binding(
                                    get: { enabled },
                                    set: { on in
                                        if on { settings.clock.hiddenCalendarIDs.remove(cal.id) }
                                        else { settings.clock.hiddenCalendarIDs.insert(cal.id) }
                                    }
                                )) {
                                    HStack(spacing: 6) {
                                        Circle().fill(Color(red: cal.red, green: cal.green, blue: cal.blue)).frame(width: 8, height: 8)
                                        Text(cal.title)
                                        if !cal.source.isEmpty {
                                            Text(cal.source).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                case .notAsked:
                    LabeledContent("Calendar access") {
                        Button("Allow Access…") { store.activate(requestAccess: true) }
                    }
                case .restricted:
                    LabeledContent("Calendar access") {
                        Text("Restricted on this Mac").foregroundStyle(.secondary)
                    }
                case .denied, .writeOnly:
                    LabeledContent("Calendar access") {
                        Button("Open Privacy Settings…") { CalendarStore.openPrivacySettings() }
                    }
                }
            }
        } header: {
            Text("Calendar & meetings")
        } footer: {
            Text("Reads Apple Calendar locally via EventKit (iCloud, Google, Exchange and Outlook accounts configured in macOS). Nothing is uploaded.").settingsFooter()
        }
        .onAppear {
            if settings.clock.showCalendarEvents { store.activate(requestAccess: false) }
        }
    }
}

private struct NextEventSettingsSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Show next event in the menu bar", isOn: $settings.clock.nextEventInMenuBar)
            if settings.clock.nextEventInMenuBar {
                Toggle("Show event title", isOn: $settings.clock.nextEventShowTitle)
                Toggle("Show Join button for upcoming video calls", isOn: $settings.clock.nextEventShowJoinButton)
                Toggle("Only show video call events", isOn: $settings.clock.nextEventOnlyVideoCalls)
                Toggle("Keep showing while event is in progress", isOn: $settings.clock.nextEventShowDuringEntireEvent)
                Toggle("Click to join video call when starting soon", isOn: $settings.clock.nextEventClickToJoin)
                Picker("Look ahead", selection: $settings.clock.nextEventLookaheadHours) {
                    Text("1 hour").tag(1)
                    Text("2 hours").tag(2)
                    Text("4 hours").tag(4)
                    Text("8 hours").tag(8)
                    Text("24 hours").tag(24)
                }
                Picker("Maximum width", selection: $settings.clock.nextEventMaxWidth) {
                    Text("Compact (120 pt)").tag(120)
                    Text("Standard (160 pt)").tag(160)
                    Text("Wide (200 pt)").tag(200)
                }
            }
        } header: {
            Text("Upcoming event in menu bar")
        } footer: {
            Text("Shows a compact standalone item when a meeting is coming up, and hides automatically when your schedule is clear. Right-click it for Join and Hide actions.").settingsFooter()
        }
    }
}

private struct MeetingAlertsSettingsSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            Picker("Alert style", selection: $settings.clock.meetingAlertStyle) {
                ForEach(MeetingAlertStyle.allCases) { Text($0.title).tag($0) }
            }
            if settings.clock.meetingAlertStyle != .off {
                Picker("Notify before start", selection: $settings.clock.meetingAlertLeadMinutes) {
                    Text("At start time").tag(0)
                    Text("1 minute before").tag(1)
                    Text("2 minutes before").tag(2)
                    Text("5 minutes before").tag(5)
                }
                Toggle("Only for video call events", isOn: $settings.clock.meetingAlertOnlyVideoCalls)
                Toggle("Only for events with a calendar alert", isOn: $settings.clock.meetingAlertOnlyWithAlarm)
                if settings.clock.meetingAlertStyle == .fullscreen {
                    Toggle("Downgrade to banner while already on a call", isOn: $settings.clock.meetingAlertSuppressDuringCall)
                    Toggle("Play alert sound", isOn: $settings.clock.meetingAlertPlaySound)
                }
                LabeledContent("Try it out") {
                    Button("Preview Fullscreen Alert") { MeetingAlertManager.shared.showPreview() }
                }
            }
        } header: {
            Text("Meeting notifications")
        } footer: {
            Text("Fullscreen alerts span your connected displays with one-click Join and Snooze, and automatically downgrade to a quiet banner if your display is mirrored (AirPlay/projector) or pause during a Focus filter.").settingsFooter()
        }
    }
}

private struct HourlyChimeSettingsSection: View {
    @Environment(AppSettings.self) private var settings

    private static func hourLabel(_ minutes: Int) -> String {
        let comps = DateComponents(calendar: .current, hour: minutes / 60, minute: minutes % 60)
        return comps.date?.formatted(date: .omitted, time: .shortened) ?? "\(minutes / 60):00"
    }

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Play an hourly chime", isOn: $settings.clock.hourlyChimeEnabled)
            if settings.clock.hourlyChimeEnabled {
                Picker("Frequency", selection: $settings.clock.hourlyChimeCadence) {
                    ForEach(ChimeCadence.allCases) { Text($0.title).tag($0) }
                }
                HStack {
                    Picker("Sound", selection: $settings.clock.hourlyChimeSound) {
                        ForEach(ChimeSound.allCases) { Text($0.title).tag($0) }
                    }
                    Button("Play") {
                        HourlyChimeManager.shared.preview(sound: settings.clock.hourlyChimeSound,
                                                          volume: settings.clock.hourlyChimeVolume)
                    }
                    .controlSize(.small)
                }
                LabeledContent("Volume") {
                    Slider(value: $settings.clock.hourlyChimeVolume, in: 0.1...1.0)
                        .frame(width: 150)
                }
                Picker("Active from", selection: $settings.clock.hourlyChimeStartMinute) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(Self.hourLabel(hour * 60)).tag(hour * 60)
                    }
                }
                Picker("Until", selection: $settings.clock.hourlyChimeEndMinute) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(Self.hourLabel(hour * 60)).tag(hour * 60)
                    }
                }
            }
        } header: {
            Text("Hourly chime")
        } footer: {
            Text("Plays a subtle macOS system sound on the hour during your active hours. Automatically muted during calls, screen lock, or a Focus filter.").settingsFooter()
        }
    }
}

// MARK: - To-do

private struct TodoSections: View {
    @Environment(AppSettings.self) private var settings
    private var store: RemindersStore { .shared }

    var body: some View {
        Section {
            switch store.access {
            case .granted:
                Picker("List", selection: Binding(get: { settings.todo.listID }, set: { settings.todo.listID = $0 })) {
                    Text(defaultTitle).tag("")
                    ForEach(store.lists) { Text($0.title).tag($0.id) }
                    // A saved list that's gone (deleted, or from another Mac) still needs a tag; it falls back to the default.
                    if !settings.todo.listID.isEmpty, !store.lists.contains(where: { $0.id == settings.todo.listID }) {
                        Text(defaultTitle).tag(settings.todo.listID)
                    }
                }
            case .notAsked:
                LabeledContent("Reminders") {
                    Button("Allow Access…") { store.activate(requestAccess: true) }
                }
            case .restricted:
                LabeledContent("Reminders") { Text("Restricted on this Mac").foregroundStyle(.secondary) }
            case .denied, .writeOnly:
                LabeledContent("Reminders") {
                    Button("Open Privacy Settings…") { RemindersStore.openPrivacySettings() }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text(footer).settingsFooter()
        }
        .onAppear { if settings.isEnabled(.todo) { store.activate(requestAccess: false) } }
    }

    private var defaultTitle: String {
        let name = store.lists.first { $0.id == store.defaultListID }?.title
        return name.map { String(localized: "Default (\($0))") } ?? String(localized: "Default list")
    }

    private var footer: String {
        switch store.access {
        case .denied, .writeOnly:
            String(localized: "VibeCheck isn't allowed to read Reminders. Turn it on in System Settings › Privacy & Security › Reminders.")
        default:
            String(localized: "Tasks live in Apple Reminders, so they sync with your iPhone through iCloud. VibeCheck shows one list and only changes it when you add, tick off or delete a task.")
        }
    }
}

// MARK: - Weather

private struct WeatherSections: View {
    @Environment(AppSettings.self) private var settings
    @State private var search = ""
    @State private var results: [WeatherLocation] = []
    @State private var searching = false
    @State private var searchError: String?

    var body: some View {
        @Bindable var settings = settings
        Section("Forecast") {
            Picker("Units", selection: $settings.weather.unit) {
                ForEach(TemperatureUnit.allCases) { Text($0.title).tag($0) }
            }
            LabeledContent("City") {
                if let location = settings.weather.location {
                    VStack(alignment: .trailing) {
                        Text(location.name)
                        if location.subtitle != location.name {
                            Text(location.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Not set").foregroundStyle(.secondary)
                }
            }
        }

        Section {
            TextField("Search for a city", text: $search)
                .task(id: search) { await runSearch() }
            if searching { ProgressView().controlSize(.small) }
            if let searchError { Text(searchError).font(.caption).foregroundStyle(.secondary) }
            ForEach(results) { place in
                HStack {
                    VStack(alignment: .leading) {
                        Text(place.name)
                        Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Use") {
                        settings.weather.location = place
                        search = ""
                        results = []
                    }
                }
            }
        } header: {
            Text("Change city")
        } footer: {
            Text("Weather comes from Open-Meteo.com (free, no account). Only what you type here and the chosen city's coordinates are sent; VibeCheck never asks for your location.")
                .settingsFooter()
        }
    }

    /// Debounced: waits until typing pauses before asking the geocoder.
    private func runSearch() async {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { results = []; searchError = nil; return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        do {
            results = try await OpenMeteo.search(query)
            searchError = results.isEmpty ? String(localized: "No matches.") : nil
        } catch {
            if !Task.isCancelled { searchError = String(localized: "Search failed. Check your connection.") }
        }
    }
}

/// Network page: the opt-in public IP lookup.
private struct PublicIPSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Show public IP address", isOn: $settings.showPublicIP)
        } footer: {
            Text("Off by default. When on, VibeCheck asks api.ipify.org (over HTTPS) for your address at most every 10 minutes and when your network changes. That service sees your IP, as any website does.")
                .settingsFooter()
        }
    }
}
