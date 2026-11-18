import SwiftUI

struct SettingsView: View {
    let onTestNotification: () -> Void

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AlertSettings(onTestNotification: onTestNotification)
                .tabItem { Label("Alerts", systemImage: "bell.badge") }
            ClockSettings()
                .tabItem { Label("Clock", systemImage: "clock") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 500, height: 540)
    }
}

private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Menu bar") {
                Picker("Style", selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                ForEach(Module.allCases) { module in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { settings.isEnabled(module) },
                            set: { settings.setEnabled(module, $0) }
                        )) {
                            Label(module.title, systemImage: module.symbol)
                        }
                        .disabled(settings.isEnabled(module) && settings.enabledModules.count == 1)
                        Spacer()
                        Picker("Display", selection: Binding(
                            get: { settings.labelStyle(module) },
                            set: { settings.setLabelStyle($0, for: module) }
                        )) {
                            ForEach(module.labelStyles) { Text($0.title(for: module)).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .disabled(!settings.isEnabled(module))
                    }
                }
                Toggle("Colorful menu bar graphs", isOn: $settings.colorfulMenuBar)
                Picker("Spacing", selection: $settings.menuBarSpacing) {
                    ForEach(MenuBarSpacing.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(settings.menuBarStyle == .combined
                     ? "Spacing tightens the gaps inside each stat and between stats in the combined item."
                     : "Spacing tightens the padding inside each item. macOS controls the gap between separate items; use one combined item for the tightest layout.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("General") {
                Picker("Update every", selection: $settings.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
            Section {
                Text("VibeCheck 1.2 · Click any menu bar item to check the vibes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AlertSettings: View {
    let onTestNotification: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                if settings.alertRules.isEmpty {
                    Text("No alerts yet.").foregroundStyle(.secondary)
                }
                ForEach($settings.alertRules) { $rule in
                    AlertRuleRow(rule: $rule) {
                        settings.alertRules.removeAll { $0.id == rule.id }
                    }
                }
            } header: {
                Text("Notify me when…")
            } footer: {
                Text("Each alert fires once, then waits until the value is back to normal (and at least 5 minutes) before it can fire again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Add Alert") {
                        settings.alertRules.append(AlertRule(metric: .cpu, comparison: .above, threshold: 80, duration: 60))
                    }
                    Button("Restore Defaults") { settings.alertRules = AlertRule.defaults }
                    Spacer()
                    Button("Send Test Notification", action: onTestNotification)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AlertRuleRow: View {
    @Binding var rule: AlertRule
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Enabled", isOn: $rule.enabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                Picker("Metric", selection: $rule.metric) {
                    ForEach(AlertMetric.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Delete alert")
            }
            HStack(spacing: 6) {
                Text("is")
                Picker("Comparison", selection: $rule.comparison) {
                    ForEach(AlertComparison.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().fixedSize()
                TextField("Threshold", value: threshold, format: .number)
                    .labelsHidden().frame(width: 50).multilineTextAlignment(.trailing)
                Text(rule.metric.unit)
                Text("for")
                Picker("Duration", selection: $rule.duration) {
                    ForEach(AlertRule.durations, id: \.0) { Text($0.1).tag($0.0) }
                }
                .labelsHidden().fixedSize()
            }
            .disabled(!rule.enabled)
        }
        .padding(.vertical, 2)
        .onChange(of: rule.metric) { _, metric in
            rule.comparison = (metric == .batteryLevel || metric == .diskFree) ? .below : .above
            rule.threshold = min(max(rule.threshold, metric.range.lowerBound), metric.range.upperBound)
        }
    }

    private var threshold: Binding<Double> {
        Binding(get: { rule.threshold }, set: { value in
            let r = rule.metric.range
            rule.threshold = min(max(value, r.lowerBound), r.upperBound)
        })
    }
}

private struct ShortcutSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Enable keyboard shortcuts", isOn: $settings.hotkeysEnabled)
                Picker("Modifier keys", selection: $settings.hotkeyModifier) {
                    ForEach(HotkeyModifier.allCases) { Text($0.symbols).tag($0) }
                }
                .disabled(!settings.hotkeysEnabled)
            }
            Section("Shortcuts") {
                ForEach(Array(Module.allCases.enumerated()), id: \.element) { index, module in
                    HStack {
                        Label(module.title, systemImage: module.symbol)
                        Spacer()
                        Text("\(settings.hotkeyModifier.symbols)\(index + 1)")
                            .font(.body.monospaced())
                            .foregroundStyle(settings.isEnabled(module) ? .primary : .tertiary)
                    }
                }
            }
            Section {
                Text("Press a shortcut from any app to open that panel; press it again to close. Shortcuts for items that are switched off just beep.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ClockSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var search = ""

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Menu bar clock") {
                Toggle("Show clock in menu bar", isOn: Binding(
                    get: { settings.isEnabled(.clock) },
                    set: { settings.setEnabled(.clock, $0) }
                ))
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
                    }
                }
            }

            Section("Add a world clock") {
                TextField("Search cities or time zones", text: $search)
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
        .formStyle(.grouped)
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
