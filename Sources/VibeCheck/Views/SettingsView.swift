import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A page of the Settings window. App-wide pages first, then one page per module.
enum SettingsSection: Hashable, Identifiable {
    case general, menuBar, keepAwake, clipboard, alerts, shortcuts, backup, about, support
    case module(Module)

    /// The sidebar, top to bottom: app pages, then monitors, then extras (like
    /// System Settings: general things first, then one row per thing you can configure).
    static let groups: [SettingsGroup] = [
        SettingsGroup(title: nil, sections: [.general, .menuBar, .keepAwake, .clipboard, .alerts, .shortcuts, .backup, .about, .support]),
        SettingsGroup(title: String(localized: "Monitors"), sections: Module.allCases.filter { !$0.isExtra }.map { .module($0) }),
        SettingsGroup(title: String(localized: "Extras"), sections: Module.allCases.filter(\.isExtra).map { .module($0) }),
    ]

    static var allCases: [SettingsSection] { groups.flatMap(\.sections) }

    var id: String {
        switch self {
        case .general: "general"
        case .menuBar: "menuBar"
        case .keepAwake: "keepAwake"
        case .clipboard: "clipboard"
        case .alerts: "alerts"
        case .shortcuts: "shortcuts"
        case .backup: "backup"
        case .about: "about"
        case .support: "support"
        case .module(let module): "module.\(module.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .menuBar: String(localized: "Menu Bar")
        case .keepAwake: String(localized: "Keep Awake")
        case .clipboard: String(localized: "Clipboard")
        case .alerts: String(localized: "Alerts")
        case .shortcuts: String(localized: "Shortcuts")
        case .backup: String(localized: "Backup")
        case .about: String(localized: "About")
        case .support: String(localized: "Support")
        case .module(let module): module.title
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .menuBar: "menubar.rectangle"
        case .keepAwake: "cup.and.saucer.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .alerts: "bell.badge.fill"
        case .shortcuts: "command"
        case .backup: "externaldrive.fill.badge.timemachine"
        case .about: "info"
        case .support: "heart.fill"
        case .module(let module): module.symbol
        }
    }

    /// Tile color behind the sidebar symbol (System Settings style: white glyph on a colored square).
    var color: Color {
        switch self {
        case .general: .gray
        case .menuBar: .blue
        case .keepAwake: .brown
        case .clipboard: .orange
        case .alerts: .red
        case .shortcuts: .indigo
        case .backup: .teal
        case .about: .gray
        case .support: .pink
        case .module(let module): module.accent
        }
    }

    /// Extra words the sidebar search matches, so "notch" finds Menu Bar and "caffeinate" finds Keep Awake.
    var keywords: String {
        switch self {
        case .general: "update interval refresh launch login startup quick toggles mute trash bluetooth sleep advanced sampling"
        case .menuBar: "style combined separate items spacing ring notch colorful order reorder preview advanced graphs camera"
        case .keepAwake: "caffeinate sleep display focus timer schedule power downloads agents"
        case .clipboard: "paste copy history snippets pinned ignore password clear"
        case .alerts: "notifications warnings thresholds advanced restore defaults test"
        case .shortcuts: "hotkeys keyboard global modifier secure input advanced"
        case .backup: "export import reset defaults restore"
        case .about: "version"
        case .support: "buy me a coffee donate tip thanks sponsor"
        case .module(let module): "\(module.settingsKeywords) \(module.settingsSummary) menu bar alerts shortcut advanced"
        }
    }

    func matches(_ query: String) -> Bool {
        let words = query.split(separator: " ")
        let haystack = "\(title) \(keywords)"
        return words.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
    }
}

struct SettingsGroup: Identifiable {
    let title: String?
    let sections: [SettingsSection]
    var id: String { title ?? "app" }
}

/// Which Settings page is showing; shared so other parts of the app can open a specific page.
@Observable
@MainActor
final class SettingsRouter {
    static let shared = SettingsRouter()
    var section: SettingsSection? = .menuBar
    /// Sidebar search text; cleared by `open` so the page you jump to is visible in the list.
    var query = ""

    func open(_ section: SettingsSection) {
        query = ""
        self.section = section
    }
}

/// Sidebar settings window: grouped, searchable list on the left, one page per row on the right.
struct SettingsView: View {
    let onTestNotification: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var router = SettingsRouter.shared
        let section = router.section ?? .menuBar
        NavigationSplitView {
            List(selection: $router.section) {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.sections) { row($0) }
                    } header: {
                        if let title = group.title { Text(title) }
                    }
                }
            }
            .searchable(text: $router.query, placement: .sidebar, prompt: "Search settings")
            .overlay {
                if groups.isEmpty {
                    ContentUnavailableView.search(text: router.query)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            page(section)
                .id(section) // fresh scroll position and @State per page
                .navigationTitle(section.title)
        }
        // Search can hide the selected row, and List then clears the selection; keep the page instead.
        .onChange(of: router.section) { old, new in
            if new == nil, let old { router.section = old }
        }
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 720, minHeight: 540)
    }

    private var groups: [SettingsGroup] {
        let trimmed = SettingsRouter.shared.query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return SettingsSection.groups }
        return SettingsSection.groups.compactMap { group in
            let hits = group.sections.filter { $0.matches(trimmed) }
            return hits.isEmpty ? nil : SettingsGroup(title: group.title, sections: hits)
        }
    }

    private func row(_ section: SettingsSection) -> some View {
        Label {
            HStack {
                Text(section.title)
                Spacer(minLength: 4)
                if case .module(let module) = section, !settings.isEnabled(module) {
                    Text("Off").font(.caption).foregroundStyle(.tertiary)
                }
            }
        } icon: {
            if section == .about {
                // The app icon carries Apple's ~10% transparent margin; enlarge it so its plate matches the tiles.
                Image(nsImage: NSApp.applicationIconImage).resizable()
                    .frame(width: 20 * 1.24, height: 20 * 1.24)
                    .frame(width: 20, height: 20)
            } else {
                SettingsIcon(symbol: section.symbol, color: section.color, size: 20)
            }
        }
        .tag(section)
    }

    @ViewBuilder
    private func page(_ section: SettingsSection) -> some View {
        switch section {
        case .general: GeneralSettings()
        case .menuBar: MenuBarSettings()
        case .keepAwake: KeepAwakeSettings()
        case .clipboard: ClipboardSettings()
        case .alerts: AlertSettings(onTestNotification: onTestNotification)
        case .shortcuts: ShortcutSettings()
        case .backup: BackupSettings()
        case .about: AboutSettings()
        case .support: SupportSettings()
        case .module(let module): ModuleSettings(module: module)
        }
    }
}

/// White SF Symbol on a colored rounded square, the System Settings sidebar look.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        shape
            .fill(color.gradient)
            .overlay(
                // Scaled to fit one fixed box rather than set by font size: wide or badged symbols (battery,
                // the Time Machine drive, bell.badge) otherwise overflow the tile, and List sidebars enlarge
                // label icons on top of that.
                Image(systemName: symbol)
                    .resizable()
                    .symbolRenderingMode(.monochrome)
                    .fontWeight(.semibold)
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: size * 0.62, height: size * 0.62)
            )
            .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .clipShape(shape)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Menu Bar

private struct MenuBarSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var itemDrag = ItemDrag()

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                MenuBarPreview()
            } header: {
                Text("Preview")
            } footer: {
                Text("Live, using your real stats. With separate items macOS sets the gaps between them. Reordering below moves them in the menu bar too; ⌘-dragging there works as well, until the next reorder here.")
                    .settingsFooter()
            }

            Section("Style") {
                Picker("Show as", selection: $settings.menuBar.style) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Toggle("Show vibe ring", isOn: $settings.menuBar.showVibeRing)
                    .disabled(settings.menuBar.style == .ring)
            }

            AdvancedSection {
                Picker("Spacing", selection: $settings.menuBar.spacing) {
                    ForEach(MenuBarSpacing.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Colorful graphs", isOn: $settings.menuBar.colorful)
                Toggle(isOn: $settings.menuBar.autoFitNotch) {
                    Text("Fit around the camera notch")
                    Text("On a display with a notch, the combined item shows as many stats as fit beside it (in the order below) plus a +N badge. Everything stays in the deck.")
                }
                .disabled(settings.menuBar.style != .combined)
                Picker("Stats beside the notch", selection: $settings.menuBar.notchMaxStats) {
                    Text("As many as fit").tag(0)
                    ForEach(1...4, id: \.self) { Text("At most \($0)").tag($0) }
                }
                .disabled(!settings.menuBar.autoFitNotch || settings.menuBar.style != .combined)
                if settings.menuBar.style != .combined {
                    Text("The notch options only apply to \"One combined item\". With separate items, macOS hides whatever doesn't fit beside the notch.")
                        .settingsFooter()
                }
            }

            Section {
                ForEach(settings.moduleOrder) { module in
                    ModuleRow(module: module, drag: itemDrag)
                }
            } header: {
                Text("Items")
            } footer: {
                Text("Drag to reorder, or right-click a row for Move Up / Move Down. The menu bar items, the combined item and the deck follow this order. Click › for an item's options and alerts.")
                    .settingsFooter()
            }
        }
        .settingsForm()
    }
}

/// Live state of a drag in the Items list: which row is moving and the gap it would drop into.
@Observable
private final class ItemDrag {
    var dragging: Module?
    /// Insertion index into `moduleOrder` (0...count); nil when the drop would change nothing.
    var gap: Int?
    /// True while the drag is over the list; a cancelled or finished drag clears it.
    var isOver = false
}

private struct ItemDropDelegate: DropDelegate {
    let module: Module
    let rowHeight: CGFloat
    let settings: AppSettings
    let drag: ItemDrag

    func dropUpdated(info: DropInfo) -> DropProposal? {
        drag.isOver = true
        guard let dragged = drag.dragging,
              let from = settings.moduleOrder.firstIndex(of: dragged),
              let index = settings.moduleOrder.firstIndex(of: module) else { return DropProposal(operation: .move) }
        let gap = info.location.y < rowHeight / 2 ? index : index + 1
        drag.gap = (gap == from || gap == from + 1) ? nil : gap
        return DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) { _ = dropUpdated(info: info) }

    func dropExited(info: DropInfo) {
        drag.isOver = false
        drag.gap = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { drag.dragging = nil; drag.gap = nil; drag.isOver = false }
        guard let dragged = drag.dragging, let gap = drag.gap,
              let from = settings.moduleOrder.firstIndex(of: dragged) else { return false }
        withAnimation(.snappy(duration: 0.2)) { settings.moveModules(from: [from], to: gap) }
        return true
    }
}

private struct ModuleRow: View {
    let module: Module
    let drag: ItemDrag
    @Environment(AppSettings.self) private var settings
    @State private var rowHeight: CGFloat = 28

    private var index: Int? { settings.moduleOrder.firstIndex(of: module) }
    private var isDragged: Bool { drag.isOver && drag.dragging == module }
    private var lineAbove: Bool { drag.gap != nil && drag.gap == index }
    private var lineBelow: Bool { drag.gap != nil && drag.gap == settings.moduleOrder.count && index == settings.moduleOrder.count - 1 }

    var body: some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 20, height: 28)
                .contentShape(Rectangle())
                .onHover { inside in if inside { NSCursor.openHand.push() } else { NSCursor.pop() } }
                .accessibilityHidden(true)
            Toggle(isOn: Binding(get: { settings.isEnabled(module) }, set: { settings.setEnabled(module, $0) })) {
                Label {
                    Text(module.title)
                } icon: {
                    SettingsIcon(symbol: module.symbol, color: module.accent, size: 18)
                }
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
            Button {
                SettingsRouter.shared.open(.module(module))
            } label: {
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("\(module.title) settings")
            .accessibilityLabel("\(module.title) settings")
        }
        // Grouped Forms on macOS ignore .onMove (it only works in a List), so rows reorder by drag and drop.
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
        .opacity(isDragged ? 0.35 : 1)
        .overlay(alignment: .top) { insertionLine.opacity(lineAbove ? 1 : 0).offset(y: -5) }
        .overlay(alignment: .bottom) { insertionLine.opacity(lineBelow ? 1 : 0).offset(y: 5) }
        .animation(.easeOut(duration: 0.12), value: drag.gap)
        .onDrag {
            drag.dragging = module
            return NSItemProvider(object: module.rawValue as NSString)
        } preview: {
            Label { Text(module.title) } icon: { SettingsIcon(symbol: module.symbol, color: module.accent, size: 18) }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .onDrop(of: [.plainText], delegate: ItemDropDelegate(module: module, rowHeight: rowHeight, settings: settings, drag: drag))
        .contextMenu {
            if let index = settings.moduleOrder.firstIndex(of: module) {
                Button("Move Up") { settings.moveModules(from: [index], to: max(0, index - 1)) }
                    .disabled(index == 0)
                Button("Move Down") { settings.moveModules(from: [index], to: min(settings.moduleOrder.count, index + 2)) }
                    .disabled(index == settings.moduleOrder.count - 1)
            }
            Divider()
            Button("\(module.title) Settings…") { SettingsRouter.shared.open(.module(module)) }
        }
    }

    /// Accent bar with a dot at the leading end, Finder-style, marking where the dragged item will land.
    private var insertionLine: some View {
        HStack(spacing: 0) {
            Circle().strokeBorder(Color.accentColor, lineWidth: 2).frame(width: 8, height: 8)
            Rectangle().fill(Color.accentColor).frame(height: 2)
        }
        .frame(height: 8)
        .allowsHitTesting(false)
    }
}

/// A slice of menu bar drawn with the real labels, so what you see here is what you get.
private struct MenuBarPreview: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                Spacer(minLength: 0)
                if settings.menuBar.style == .combined {
                    CombinedLabel()
                } else {
                    HStack(spacing: 10) {
                        if settings.menuBar.ringVisible { VibeItemLabel() }
                        if settings.menuBar.style != .ring { ForEach(settings.orderedModules) { MenuBarLabel(module: $0) } }
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

// MARK: - General, Backup, About

private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings
    @AppStorage("showQuickToggles") private var showQuickToggles = true

    private var bluetoothFooter: String {
        let snooze = BluetoothSnooze.shared
        guard snooze.isAvailable else { return String(localized: "Not available on this version of macOS.") }
        let about = String(localized: "Stops a sleeping Mac from grabbing headphones you also use with your phone. Bluetooth comes back on when the Mac wakes, if it was on before. While asleep, a Bluetooth keyboard or mouse can't wake the Mac, and Apple Watch unlock won't work.")
        if settings.keepAwake.bluetoothOffWhileAsleep, snooze.access == .denied {
            return String(localized: "VibeCheck isn't allowed to use Bluetooth, so this does nothing. Allow it in System Settings → Privacy & Security → Bluetooth. ") + about
        }
        return about
    }

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
            Section {
                Toggle("Show quick toggles in the deck", isOn: $showQuickToggles)
            } header: {
                Text("Deck")
            } footer: {
                Text("A row for microphone mute. Empty Trash is in the ⌘K palette and asks macOS for Automation access the first time.")
                    .settingsFooter()
            }
            AdvancedSection {
                Picker("Update every", selection: $settings.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
                Toggle("Turn Bluetooth off while the Mac sleeps", isOn: $settings.keepAwake.bluetoothOffWhileAsleep)
                    .disabled(!BluetoothSnooze.shared.isAvailable)
                Text(bluetoothFooter).settingsFooter()
            }
        }
        .settingsForm()
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
        .settingsForm()
    }
}

private struct AboutSettings: View {
    @Environment(AppSettings.self) private var settings
    private var updates = UpdateChecker.shared
    /// The command whose Copy button was just pressed, so it can say "Copied" for a moment.
    @State private var copied: String?

    private static let licenseURL = URL(string: "https://github.com/saroj-shahi/vibecheck/blob/main/LICENSE")!

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = command
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if copied == command { copied = nil }
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.5"
    }

    @ViewBuilder private var updateStatus: some View {
        switch updates.state {
        case .idle:
            EmptyView()
        case .noInfo:
            Text("No release information yet.").foregroundStyle(.secondary)
        case .checking:
            Text("Checking…").foregroundStyle(.secondary)
        case .upToDate:
            Label("You're up to date.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
        case .available(let release):
            HStack {
                Text("VibeCheck \(release.version) is out")
                Spacer()
                Button("Release Notes") { NSWorkspace.shared.open(release.pageURL) }
            }
            Text("Update from Terminal with the command that matches how you installed VibeCheck:")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(UpdateChecker.updateCommands) { item in
                LabeledContent {
                    Button(copied == item.command ? "Copied" : "Copy") { copy(item.command) }
                        .frame(minWidth: 64)
                        .accessibilityLabel(Text("Copy \(item.label) command"))
                } label: {
                    Text(item.label)
                    Text(item.command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
        }
    }

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    Text("VibeCheck").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Mac health in one ring").foregroundStyle(.secondary)
                    Text("Version \(version)").font(.caption).foregroundStyle(.tertiary)
                    Link("Free software under GPL-3.0, no warranty", destination: Self.licenseURL).font(.caption)
                    Text(verbatim: "© 2026 Saroj Shahi").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
                LabeledContent("Look for a newer version now") {
                    HStack(spacing: 8) {
                        if updates.state == .checking { ProgressView().controlSize(.small) }
                        Button("Check Now") { Task { await updates.check() } }
                            .disabled(updates.state == .checking)
                    }
                }
                updateStatus
            }
            Section("Getting around") {
                LabeledContent("Check the vibes", value: "Click the menu bar item")
                LabeledContent("Open a module from anywhere", value: "\(settings.hotkeyModifier.symbols)1–9, 0")
                LabeledContent("Find anything in the deck", value: "⌘K")
                LabeledContent("Open Settings from the deck", value: "⌘,")
            }
        }
        .settingsForm()
    }
}

// MARK: - Support

private struct SupportSettings: View {
    private static let coffeeURL = URL(string: "https://buymeacoffee.com/sarojshahi")!

    var body: some View {
        Form {
            Section {
                VStack(spacing: 14) {
                    SettingsIcon(symbol: "heart.fill", color: .pink, size: 72)
                        .accessibilityHidden(true)
                    Text("Enjoying VibeCheck?").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("VibeCheck is free, with no ads, accounts or tracking, and it stays that way. If it saves you a few minutes of squinting at Activity Monitor, a coffee says thanks.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 400)
                    Button {
                        NSWorkspace.shared.open(Self.coffeeURL)
                    } label: {
                        Label("Buy Me a Coffee", systemImage: "mug.fill")
                            .font(.title3.weight(.semibold))
                            .frame(minWidth: 240)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                    .tint(.orange)
                    .padding(.top, 6)
                    Text(verbatim: "buymeacoffee.com/sarojshahi").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            Section {
                Text("Bug reports, ideas and a star on GitHub help too.")
                    .foregroundStyle(.secondary)
            }
        }
        .settingsForm()
    }
}

// MARK: - Shortcuts

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
            }
            AdvancedSection {
                Picker("Modifier keys", selection: $settings.hotkeyModifier) {
                    ForEach(HotkeyModifier.allCases) { Text($0.symbols).tag($0) }
                }
                .disabled(!settings.hotkeysEnabled)

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
                Toggle("\(settings.hotkeyModifier.symbols)V opens clipboard history", isOn: $settings.clipboardHotkey)
                Toggle("\(settings.hotkeyModifier.symbols)F finds your cursor", isOn: $settings.findCursorHotkey)
            }
            .disabled(!settings.hotkeysEnabled)
            Section {
                Text("Press a shortcut from any app to open that panel; press it again to close. Shortcuts for items that are switched off just beep. \(settings.hotkeyModifier.symbols)A starts or stops keeping your Mac awake (see Keep Awake).")
                    .settingsFooter()
            }
        }
        .settingsForm()
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

/// Collapsed "Advanced" section for rarely changed options; rows only (no nested sections).
struct AdvancedSection<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Section {
            DisclosureGroup("Advanced") { content }
        }
    }
}

extension View {
    /// Every Settings page: grouped form with roomier margins than the system default.
    func settingsForm() -> some View {
        formStyle(.grouped)
            .contentMargins(.vertical, 8, for: .scrollContent) // added to the form's own 20: 28 top and bottom
            .padding(.horizontal, 8) // grouped forms ignore horizontal contentMargins; 20 + 8 at the sides
            .environment(\.defaultMinListRowHeight, 36)
    }

    /// Form section footer: caption, secondary, leading-aligned (grouped forms align footers trailing by default).
    func settingsFooter() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }
}
