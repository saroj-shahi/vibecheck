import AppKit
import SwiftUI

// MARK: - One page per module

extension Module {
    /// Clock and Weather sit under "Extras" in the Settings sidebar; the rest are monitors.
    var isExtra: Bool { self == .clock || self == .weather }

    /// One line under the module's name at the top of its Settings page.
    var settingsSummary: String {
        switch self {
        case .cpu: "How hard the processor is working, and which apps are pushing it."
        case .gpu: "Graphics load from games, video and machine learning."
        case .memory: "Memory in use, memory pressure and the apps holding the most."
        case .network: "Download and upload speed, the apps doing the talking and listening ports."
        case .disk: "Free space on the startup disk, and read and write speed."
        case .sensors: "Temperatures and fan speeds from the Mac's own sensors."
        case .battery: "Charge, time left and health, plus Bluetooth accessories and USB devices."
        case .agents: "Tokens and plan limits for Claude Code, Codex, Copilot and OpenCode."
        case .clock: "A menu bar clock, with world clocks in the deck."
        case .weather: "Today's forecast for one city, from Open-Meteo."
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
        case .agents: "ai claude codex copilot opencode tokens limits usage"
        case .clock: "time world time zone seconds"
        case .weather: "forecast city temperature units"
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
            case .agents: ClaudeLimitsSection()
            case .clock: ClockSections()
            case .weather: WeatherSections()
            default: EmptyView()
            }
            if !metrics.isEmpty { ModuleAlertsSection(module: module, metrics: metrics) }
            shortcutSection
        }
        .formStyle(.grouped)
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
        Section {
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
        } header: {
            Text("Shortcut")
        } footer: {
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
        }
        Toggle("Count all agents", isOn: Binding(get: { options.agents.isEmpty }, set: { all in
            settings.updateOptions(module) { $0.agents = all ? [] : [.claude] }
        }))
        if !options.agents.isEmpty {
            LabeledContent("Agents") {
                HStack(spacing: 12) {
                    ForEach(AgentKind.allCases) { kind in
                        Toggle(kind.title, isOn: Binding(get: { options.agents.contains(kind) }, set: { on in
                            settings.updateOptions(module) { if on { $0.agents.insert(kind) } else { $0.agents.remove(kind) } }
                        }))
                        .toggleStyle(.checkbox)
                        // At least one agent stays ticked.
                        .disabled(options.agents == [kind])
                    }
                }
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
                 ? "Asks your Claude Code for your plan usage every 5 minutes, the same data /usage shows. No model request, no Keychain access; Claude Code signs in itself."
                 : "Off: Claude Code shows its local 5-hour estimate. When on, VibeCheck asks your Claude Code for your plan usage every 5 minutes, the same data /usage shows. No model request, no Keychain access.")
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
        Section("Format") {
            Picker("Format", selection: $settings.clockFormat) {
                ForEach(ClockFormat.allCases) { format in
                    Text(format.formatter(seconds: settings.clockShowSeconds).string(from: Date())).tag(format)
                }
            }
            Toggle("Show seconds", isOn: $settings.clockShowSeconds)
        }

        Section("World clocks") {
            if settings.worldClocks.isEmpty {
                Text("No world clocks yet.").foregroundStyle(.secondary)
            }
            ForEach($settings.worldClocks) { $clock in
                HStack {
                    TextField("Name", text: $clock.name).labelsHidden().frame(maxWidth: 160)
                    Text(clock.timeZoneID).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(Date().formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: clock.timeZone)))
                        .monospacedDigit().foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        settings.worldClocks.removeAll { $0.id == clock.id }
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Remove \(clock.name)")
                }
            }
            TextField("Add a city or time zone", text: $search)
            ForEach(matches, id: \.self) { identifier in
                HStack {
                    Text(WorldClock.cityName(identifier))
                    Text(identifier).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Add") {
                        settings.worldClocks.append(WorldClock(name: WorldClock.cityName(identifier), timeZoneID: identifier))
                        search = ""
                    }
                    .disabled(settings.worldClocks.contains { $0.timeZoneID == identifier })
                }
            }
        }
    }

    private var matches: [String] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        let normalized = query.replacingOccurrences(of: " ", with: "_")
        return Array((TimeZone.knownTimeZoneIdentifiers + ["UTC"])
            .filter { $0.localizedCaseInsensitiveContains(normalized) || $0.localizedCaseInsensitiveContains(query) }
            .prefix(8))
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
            Picker("Units", selection: $settings.temperatureUnit) {
                ForEach(TemperatureUnit.allCases) { Text($0.title).tag($0) }
            }
            LabeledContent("City") {
                if let location = settings.weatherLocation {
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
                        settings.weatherLocation = place
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
            searchError = results.isEmpty ? "No matches." : nil
        } catch {
            if !Task.isCancelled { searchError = "Search failed. Check your connection." }
        }
    }
}
