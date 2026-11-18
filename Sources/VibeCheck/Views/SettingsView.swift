import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case menuBar, general, keepAwake, alerts, clock, weather, shortcuts, backup
    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBar: "Menu Bar"
        case .general: "General"
        case .keepAwake: "Keep Awake"
        case .alerts: "Alerts"
        case .clock: "Clock"
        case .weather: "Weather"
        case .shortcuts: "Shortcuts"
        case .backup: "Backup"
        }
    }

    var symbol: String {
        switch self {
        case .menuBar: "menubar.rectangle"
        case .general: "gearshape"
        case .keepAwake: "cup.and.saucer"
        case .alerts: "bell.badge"
        case .clock: "clock"
        case .weather: "cloud.sun"
        case .shortcuts: "keyboard"
        case .backup: "externaldrive.badge.timemachine"
        }
    }
}

/// Which Settings page is showing; shared so other parts of the app can open a specific page.
@Observable
@MainActor
final class SettingsRouter {
    static let shared = SettingsRouter()
    var section: SettingsSection? = .menuBar
}

/// Sidebar settings window.
struct SettingsView: View {
    let onTestNotification: () -> Void

    var body: some View {
        @Bindable var router = SettingsRouter.shared
        let section = router.section
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $router.section) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 210)
        } detail: {
            Group {
                switch section ?? .menuBar {
                case .menuBar: MenuBarSettings()
                case .general: GeneralSettings()
                case .keepAwake: KeepAwakeSettings()
                case .alerts: AlertSettings(onTestNotification: onTestNotification)
                case .clock: ClockSettings()
                case .weather: WeatherSettings()
                case .shortcuts: ShortcutSettings()
                case .backup: BackupSettings()
                }
            }
            .navigationTitle((section ?? .menuBar).title)
        }
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 700, minHeight: 520)
    }
}

// MARK: - Menu Bar

private struct MenuBarSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                MenuBarPreview()
            } header: {
                Text("Preview")
            } footer: {
                Text("Live, using your real stats. With separate items macOS sets the gaps between items, and their order is changed by ⌘-dragging them in the menu bar.")
                    .settingsFooter()
            }

            Section("Style") {
                Picker("Show as", selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Picker("Spacing", selection: $settings.menuBarSpacing) {
                    ForEach(MenuBarSpacing.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Show vibe ring", isOn: $settings.showVibeRing)
                Toggle(isOn: $settings.autoFitNotch) {
                    Text("Fit around the camera notch")
                    Text("On a display with a notch, the combined item shows as many stats as fit beside it (in the order below) plus a +N badge. Everything stays in the deck.")
                }
                .disabled(settings.menuBarStyle != .combined)
                Picker("Stats beside the notch", selection: $settings.notchMaxStats) {
                    Text("As many as fit").tag(0)
                    ForEach(1...4, id: \.self) { Text("At most \($0)").tag($0) }
                }
                .disabled(settings.menuBarStyle != .combined || !settings.autoFitNotch)
                Toggle("Colorful graphs", isOn: $settings.colorfulMenuBar)
            }

            Section {
                ForEach(settings.moduleOrder) { module in
                    ModuleRow(module: module)
                }
                .onMove { settings.moveModules(from: $0, to: $1) }
            } header: {
                Text("Items")
            } footer: {
                Text("Drag to reorder. The order is used by the combined item and the deck.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModuleRow: View {
    let module: Module
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Toggle(isOn: Binding(get: { settings.isEnabled(module) }, set: { settings.setEnabled(module, $0) })) {
                Label(module.title, systemImage: module.symbol)
            }
            .disabled(settings.isEnabled(module) && settings.enabledModules.count == 1)
            Spacer()
            Picker("Display", selection: Binding(get: { settings.labelStyle(module) },
                                                 set: { settings.setLabelStyle($0, for: module) })) {
                ForEach(module.labelStyles) { Text($0.title(for: module)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(!settings.isEnabled(module))
        }
        .contextMenu {
            if let index = settings.moduleOrder.firstIndex(of: module) {
                Button("Move Up") { settings.moveModules(from: [index], to: max(0, index - 1)) }
                    .disabled(index == 0)
                Button("Move Down") { settings.moveModules(from: [index], to: min(settings.moduleOrder.count, index + 2)) }
                    .disabled(index == settings.moduleOrder.count - 1)
            }
        }
    }
}

/// A slice of menu bar drawn with the real labels, so what you see here is what you get.
private struct MenuBarPreview: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                Spacer(minLength: 0)
                if settings.menuBarStyle == .combined {
                    CombinedLabel()
                } else {
                    HStack(spacing: 10) {
                        if settings.showVibeRing { VibeItemLabel() }
                        ForEach(settings.orderedModules) { MenuBarLabel(module: $0) }
                    }
                }
                HStack(spacing: 14) {
                    Image(systemName: "wifi")
                    Image(systemName: "switch.2")
                    Text(Date(), format: .dateTime.weekday(.abbreviated).hour().minute())
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            .frame(height: 26)
            .padding(.horizontal, 12)
        }
        .defaultScrollAnchor(.trailing)
        // Items that don't fit scroll off the leading edge; fade it so the cut reads as "more this way".
        .mask(HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 28)
            Rectangle()
        })
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.bar))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: settings.orderedModules)
        .accessibilityLabel("Menu bar preview")
    }
}

// MARK: - General & Backup

private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings

    private var bluetoothFooter: String {
        let snooze = BluetoothSnooze.shared
        guard snooze.isAvailable else { return "Not available on this version of macOS." }
        let about = "Stops a sleeping Mac from grabbing headphones you also use with your phone. Bluetooth comes back on when the Mac wakes, if it was on before. While asleep, a Bluetooth keyboard or mouse can't wake the Mac, and Apple Watch unlock won't work."
        if settings.bluetoothOffWhileAsleep, snooze.access == .denied {
            return "VibeCheck isn't allowed to use Bluetooth, so this does nothing. Allow it in System Settings → Privacy & Security → Bluetooth. " + about
        }
        return about
    }

    var body: some View {
        @Bindable var settings = settings
        @Bindable var claudeLimits = ClaudeLiveLimits.shared
        Form {
            Section {
                Picker("Update every", selection: $settings.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
            Section {
                Toggle("Turn Bluetooth off while the Mac sleeps", isOn: $settings.bluetoothOffWhileAsleep)
                    .disabled(!BluetoothSnooze.shared.isAvailable)
            } footer: {
                Text(bluetoothFooter)
                    .settingsFooter()
            }
            Section {
                Toggle("Show Claude's real plan limits", isOn: $claudeLimits.isOn)
                if claudeLimits.isOn {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(claudeLimits.statusText(now: context.date))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Reads Claude Code's sign-in from your Keychain (macOS asks first) and asks Anthropic for your plan usage. Nothing else is sent. Off by default.")
                    .settingsFooter()
            }
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("VibeCheck").font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("Is your Mac vibing or cooked?").font(.callout).foregroundStyle(.secondary)
                        Text("Version 1.5 · Click the menu bar item to check the vibes. ⌃⌥⌘1–9 and 0 open a module from anywhere.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
}

private struct BackupSettings: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Export your settings to a file") {
                    Button("Export…") { SettingsBackup.runExport() }
                }
                LabeledContent("Replace settings from a file") {
                    Button("Import…") { SettingsBackup.runImport() }
                }
            }
            Section {
                LabeledContent("Go back to the defaults (history is kept)") {
                    Button("Reset…", role: .destructive) { SettingsBackup.runReset() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Alerts

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
                            settings.alertRules.insert(AlertRule(metric: .cpu, comparison: .above, threshold: 80, duration: 60), at: 0)
                        }
                    } label: { Label("Add Alert", systemImage: "plus") }
                        .buttonStyle(.borderless)
                }
            } footer: {
                Text("Click a highlighted word to change it; drag a number sideways to adjust it (hold ⌥ for fine steps). Each alert fires once, then waits until things recover and at least 5 minutes pass.")
                    .settingsFooter()
            }
            Section {
                HStack {
                    Button("Restore Default Alerts") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { settings.alertRules = AlertRule.defaults }
                    }
                    Spacer()
                    Button("Send Test Notification", action: onTestNotification)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// "Tell me when [CPU usage] is [above] [90%] for [1 min]."
private struct AlertRuleRow: View {
    @Binding var rule: AlertRule
    let onDelete: () -> Void
    @State private var showPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Toggle("Enabled", isOn: $rule.enabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    .padding(.top, 2)
                FlowLayout(spacing: 5, lineSpacing: 6) {
                    Text("Tell me when")
                    TokenMenu(title: rule.metric.title) {
                        ForEach(AlertMetric.allCases) { metric in
                            Button(metric.title) { select(metric) }
                        }
                    }
                    Text("is")
                    TokenMenu(title: rule.comparison.rawValue) {
                        ForEach(AlertComparison.allCases) { comparison in
                            Button(comparison.rawValue) { rule.comparison = comparison }
                        }
                    }
                    NumberToken(value: $rule.threshold, unit: rule.metric.unit, range: rule.metric.range)
                    if rule.duration > 0 { Text("for") } // "below 15% instantly", not "for instantly"
                    TokenMenu(title: AlertRule.durationLabel(rule.duration)) {
                        ForEach(AlertRule.durations, id: \.0) { seconds, label in
                            Button(label) { rule.duration = seconds }
                        }
                    }
                }
                .opacity(rule.enabled ? 1 : 0.45)
                .disabled(!rule.enabled)
                Spacer(minLength: 0)
                Button { preview() } label: { Image(systemName: "eye") }
                    .buttonStyle(.borderless)
                    .help("Preview the notification")
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Delete alert")
            }
            if showPreview {
                NotificationPreview(title: "VibeCheck · \(rule.metric.title)", message: rule.describe(current: exampleValue))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.vertical, 2)
    }

    private var exampleValue: Double {
        let r = rule.metric.range
        return min(max(rule.threshold + (rule.comparison == .above ? 6 : -6), r.lowerBound), r.upperBound)
    }

    private func select(_ metric: AlertMetric) {
        rule.metric = metric
        rule.comparison = (metric == .batteryLevel || metric == .diskFree) ? .below : .above
        rule.threshold = min(max(rule.threshold, metric.range.lowerBound), metric.range.upperBound)
    }

    private func preview() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showPreview = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeOut(duration: 0.25)) { showPreview = false }
        }
    }
}

/// A highlighted word that opens a menu.
private struct TokenMenu<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        Menu { content } label: {
            Text(title).fontWeight(.medium)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 1)
        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
        .foregroundStyle(Color.accentColor)
    }
}

/// Converts a horizontal drag into a value change: 1 unit per 4 pt, or per 12 pt with ⌥ held.
enum AlertScrub {
    static func value(start: Double, dx: CGFloat, fine: Bool, range: ClosedRange<Double>) -> Double {
        let perPoint = fine ? 1.0 / 12 : 1.0 / 4
        return min(max((start + Double(dx) * perPoint).rounded(), range.lowerBound), range.upperBound)
    }
}

/// A number you can drag sideways to adjust (with a trackpad tick every 5) or click to type.
private struct NumberToken: View {
    @Binding var value: Double
    let unit: String
    let range: ClosedRange<Double>
    @State private var editing = false
    @State private var dragStart: Double?
    @State private var lastTick: Int?
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("Value", value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                          format: .number)
                    .labelsHidden()
                    .frame(width: 48)
                    .focused($focused)
                    .onSubmit { editing = false }
                    .onChange(of: focused) { _, isFocused in if !isFocused { editing = false } }
                    .onAppear { focused = true }
            } else {
                Text("\(Int(value))\(unit)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(dragStart == nil ? 0.14 : 0.26)))
                    .foregroundStyle(Color.accentColor)
                    .onHover { inside in inside ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { drag in
                            if dragStart == nil { dragStart = value }
                            let fine = NSEvent.modifierFlags.contains(.option)
                            let next = AlertScrub.value(start: dragStart ?? value, dx: drag.translation.width, fine: fine, range: range)
                            if next != value {
                                withAnimation(.snappy(duration: 0.12)) { value = next }
                                let tick = Int(next) / 5
                                if tick != lastTick {
                                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                                    lastTick = tick
                                }
                            }
                        }
                        .onEnded { _ in dragStart = nil; lastTick = nil })
                    .onTapGesture { editing = true }
                    .help("Drag sideways to adjust (⌥ for fine steps), or click to type")
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Threshold")
        .accessibilityValue("\(Int(value)) \(unit)")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 1.0 : -1.0
            value = min(max(value + step, range.lowerBound), range.upperBound)
        }
    }
}

/// A miniature of the banner the alert will post.
private struct NotificationPreview: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notification preview: \(title). \(message)")
    }
}

/// Wraps its children onto new lines when they don't fit, like words in a sentence.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += row.indices.isEmpty ? size.width : size.width + spacing
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

private struct ShortcutSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var secureInput: SecureInputStatus?

    var body: some View {
        @Bindable var settings = settings
        Form {
            if let secureInput {
                Section {
                    Label(secureInput.message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
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
                        Text(module.shortcutKey.map { "\(settings.hotkeyModifier.symbols)\($0)" } ?? "—")
                            .font(.body.monospaced())
                            .foregroundStyle(settings.isEnabled(module) ? .primary : .tertiary)
                    }
                }
            }
            Section {
                Text("Press a shortcut from any app to open that panel; press it again to close. Shortcuts for items that are switched off just beep. \(settings.hotkeyModifier.symbols)A starts or stops keeping your Mac awake (see Keep Awake).")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
        .task {
            // Only runs while this pane is visible; cancelled when it goes away.
            while !Task.isCancelled {
                let status = SecureInput.current()
                if status != secureInput { secureInput = status }
                try? await Task.sleep(for: .seconds(2))
            }
        }
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

private struct WeatherSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var search = ""
    @State private var results: [WeatherLocation] = []
    @State private var searching = false
    @State private var searchError: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Show weather in menu bar", isOn: Binding(
                    get: { settings.isEnabled(.weather) },
                    set: { settings.setEnabled(.weather, $0) }
                ))
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
                Text("Weather comes from Open-Meteo.com (free, no account). Only the chosen city's coordinates are sent; VibeCheck never asks for your location.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
        .task(id: search) { await runSearch() }
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

extension View {
    /// Form section footer: caption, secondary, leading-aligned (grouped forms align footers trailing by default).
    func settingsFooter() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
