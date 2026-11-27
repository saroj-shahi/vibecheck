import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A page of the Settings window. Core app pages first, then collapsible Monitors & Extras, then About.
enum SettingsSection: Hashable, Identifiable {
    case general, menuBar, keepAwake, alerts, clipboard, shortcuts, about
    case module(Module)

    /// The sidebar, top to bottom: 6 core panes, Monitors, Extras, and About — always expanded.
    static let groups: [SettingsGroup] = [
        SettingsGroup(id: "core", title: nil,
                      sections: [.general, .menuBar, .keepAwake, .alerts, .clipboard, .shortcuts]),
        SettingsGroup(id: "monitors", title: String(localized: "Monitors"),
                      sections: Module.allCases.filter { !$0.isExtra }.map { .module($0) }),
        SettingsGroup(id: "extras", title: String(localized: "Extras"),
                      sections: Module.allCases.filter(\.isExtra).map { .module($0) }),
        SettingsGroup(id: "about", title: nil, sections: [.about]),
    ]

    static var allCases: [SettingsSection] { groups.flatMap(\.sections) }

    static func from(id: String) -> SettingsSection? {
        allCases.first { $0.id == id }
    }

    var id: String {
        switch self {
        case .general: "general"
        case .menuBar: "menuBar"
        case .keepAwake: "keepAwake"
        case .alerts: "alerts"
        case .clipboard: "clipboard"
        case .shortcuts: "shortcuts"
        case .about: "about"
        case .module(let module): "module.\(module.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .menuBar: String(localized: "Menu Bar")
        case .keepAwake: String(localized: "Keep Awake")
        case .alerts: String(localized: "Alerts")
        case .clipboard: String(localized: "Clipboard")
        case .shortcuts: String(localized: "Shortcuts")
        case .about: String(localized: "About VibeCheck")
        case .module(let module): module.title
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .menuBar: "menubar.rectangle"
        case .keepAwake: "cup.and.saucer.fill"
        case .alerts: "bell.badge.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .shortcuts: "command"
        case .about: "info"
        case .module(let module): module.symbol
        }
    }

    /// Tile color behind the sidebar symbol (System Settings style: white glyph on a colored square).
    var color: Color {
        switch self {
        case .general: .gray
        case .menuBar: .blue
        case .keepAwake: .brown
        case .alerts: .red
        case .clipboard: .orange
        case .shortcuts: .indigo
        case .about: .gray
        case .module(let module): module.accent
        }
    }

    /// Extra words the sidebar search matches, so "notch" finds Menu Bar and "caffeinate" finds Keep Awake.
    var keywords: String {
        switch self {
        case .general: "update interval refresh launch login startup quick toggles mute trash bluetooth sleep advanced sampling opacity glass transparency popover background backup export import reset defaults privacy permissions"
        case .menuBar: "style combined separate items spacing ring notch colorful order reorder preview advanced graphs camera"
        case .keepAwake: "caffeinate sleep display focus timer schedule power downloads agents bluetooth snooze call guard wifi"
        case .alerts: "notifications warnings thresholds advanced restore defaults test smart memory leak throttling slow charger agent finished"
        case .clipboard: "paste copy history snippets pinned ignore password clear pasteboard"
        case .shortcuts: "hotkeys keyboard global modifier secure input advanced keep awake"
        case .about: "version updates release buy me a coffee donate tip thanks sponsor github"
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
    let id: String
    let title: String?
    let sections: [SettingsSection]
}

/// Sidebar settings window: spacious custom search + navigation on the left, live grouped detail on the right.
struct SettingsView: View {
    let onTestNotification: () -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedHitIndex = 0
    @FocusState private var searchFocused: Bool

    private var trimmedQuery: String {
        SettingsRouter.shared.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchHits: [SettingsSearchEntry] {
        SettingsSearchIndex.search(trimmedQuery)
    }

    private var sidebarCollapsed: Bool { columnVisibility == .detailOnly }

    var body: some View {
        @Bindable var router = SettingsRouter.shared
        let section = router.section ?? .menuBar
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                sidebarSearchField(query: $router.query)
                    .padding(.top, 14)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                sidebarList(router: $router)
            }
            .navigationSplitViewColumnWidth(min: 232, ideal: 252, max: 292)
        } detail: {
            ScrollViewReader { proxy in
                page(section)
                    .id(section)
                    .navigationTitle(section.title)
                    .onChange(of: router.highlightedControlID, initial: true) { _, anchor in
                        guard let anchor else { return }
                        Task { @MainActor in
                            // Let page/sub-tab layout finish mounting before scrolling to the anchor.
                            try? await Task.sleep(for: .milliseconds(120))
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                                proxy.scrollTo(anchor, anchor: .center)
                            }
                        }
                    }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        toggleSidebar()
                    } label: {
                        Label(sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar",
                              systemImage: "sidebar.leading")
                    }
                    .help(sidebarCollapsed ? "Show Sidebar (⌥⌘S)" : "Hide Sidebar (⌥⌘S)")
                    .keyboardShortcut("s", modifiers: [.command, .option])
                }
            }
        }
        .toolbar(removing: .sidebarToggle)
        .navigationSplitViewStyle(.balanced)
        .onChange(of: router.section) { old, new in
            if new == nil, let old { router.section = old }
        }
        .onChange(of: router.query) { _, _ in
            selectedHitIndex = 0
        }
        .onChange(of: router.searchFocusToken) { _, _ in
            focusSearch()
        }
        .background {
            Button("") { focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .onKeyPress(.escape) {
            if !router.query.isEmpty || searchFocused {
                router.query = ""
                searchFocused = false
                return .handled
            }
            return .ignored
        }
        .onAppear {
            // Avoid macOS auto-focusing the search field on initial window open; ⌘F or clicking focuses it.
            DispatchQueue.main.async {
                searchFocused = false
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .frame(minWidth: 840, minHeight: 600)
    }

    private func toggleSidebar() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)) {
            columnVisibility = sidebarCollapsed ? .all : .detailOnly
        }
    }

    private func focusSearch() {
        if sidebarCollapsed {
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)) {
                columnVisibility = .all
            }
        }
        searchFocused = true
    }

    private func commitSelectedSearchHit() {
        let hits = searchHits
        guard hits.indices.contains(selectedHitIndex) else { return }
        SettingsRouter.shared.reveal(hits[selectedHitIndex])
        searchFocused = false
    }

    /// Dedicated macOS search field with generous top breathing room, ⌘F hint, clear button, and arrow/Return nav.
    private func sidebarSearchField(query: Binding<String>) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(searchFocused ? Color.accentColor : .secondary)

            TextField("Search settings…", text: query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit { commitSelectedSearchHit() }
                .onKeyPress(.downArrow) {
                    let count = searchHits.count
                    guard count > 0 else { return .ignored }
                    selectedHitIndex = min(selectedHitIndex + 1, count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !searchHits.isEmpty else { return .ignored }
                    selectedHitIndex = max(selectedHitIndex - 1, 0)
                    return .handled
                }

            if !query.wrappedValue.isEmpty {
                Button {
                    query.wrappedValue = ""
                    selectedHitIndex = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            } else if !searchFocused {
                Text("⌘F")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.quaternary.opacity(0.8)))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(searchFocused ? 0.55 : 0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(searchFocused ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.08),
                              lineWidth: searchFocused ? 1.5 : 0.5)
        )
        .animation(.easeOut(duration: 0.14), value: searchFocused)
    }

    @ViewBuilder
    private func sidebarList(router: Bindable<SettingsRouter>) -> some View {
        if trimmedQuery.isEmpty {
            List(selection: router.section) {
                ForEach(SettingsSection.groups) { group in
                    if let title = group.title {
                        Section {
                            ForEach(group.sections) { row($0) }
                        } header: {
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                        }
                    } else {
                        Section {
                            ForEach(group.sections) { row($0) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 36)
        } else {
            let hits = searchHits
            List {
                if !hits.isEmpty {
                    Section {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { index, entry in
                            let isSelected = index == selectedHitIndex
                            Button {
                                selectedHitIndex = index
                                SettingsRouter.shared.reveal(entry)
                                searchFocused = false
                            } label: {
                                HStack(spacing: 10) {
                                    sidebarIcon(for: entry.section, size: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(entry.breadcrumb)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    if isSelected && searchFocused {
                                        Text("↩")
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isSelected ? Color.accentColor.opacity(0.16) : .clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { inside in if inside { selectedHitIndex = index } }
                        }
                    } header: {
                        Text(hits.count == 1 ? "1 match" : "\(hits.count) matches")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 44)
            .overlay {
                if hits.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }
        }
    }

    private func row(_ section: SettingsSection) -> some View {
        let isModuleOff: Bool = {
            if case .module(let module) = section { return !settings.isEnabled(module) }
            return false
        }()
        return HStack(spacing: 10) {
            sidebarIcon(for: section, size: 22)
                .opacity(isModuleOff ? 0.50 : 1)
            Text(section.title)
                .foregroundStyle(isModuleOff ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if case .module(let module) = section {
                Circle()
                    .fill(settings.isEnabled(module) ? Color.accentColor.opacity(0.78) : .clear)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isModuleOff ? String(localized: "Off") : "")
        .tag(section)
    }

    @ViewBuilder
    private func sidebarIcon(for section: SettingsSection, size: CGFloat) -> some View {
        if section == .about {
            // The app icon carries Apple's ~10% transparent margin; enlarge it so its plate matches the tiles.
            Image(nsImage: NSApp.applicationIconImage).resizable()
                .frame(width: size * 1.24, height: size * 1.24)
                .frame(width: size, height: size)
        } else {
            SettingsIcon(symbol: section.symbol, color: section.color, size: size)
        }
    }

    @ViewBuilder
    private func page(_ section: SettingsSection) -> some View {
        switch section {
        case .general: GeneralSettings()
        case .menuBar: MenuBarSettings()
        case .keepAwake: KeepAwakeSettings()
        case .alerts: AlertSettings(onTestNotification: onTestNotification)
        case .clipboard: ClipboardSettings()
        case .shortcuts: ShortcutSettings()
        case .about: AboutSettings()
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
                // bell.badge) otherwise overflow the tile, and List sidebars enlarge label icons on top of that.
                Image(systemName: symbol)
                    .resizable()
                    .symbolRenderingMode(.monochrome)
                    .fontWeight(.semibold)
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: size * 0.62, height: size * 0.62)
            )
            .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .clipShape(shape)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Menu Bar

private struct MenuBarSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var itemDrag = ItemDrag()
    @State private var hoveredModule: Module?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                MenuBarPreview(hoveredModule: $hoveredModule)
            } header: {
                HStack {
                    Text("Preview")
                    Spacer()
                    if settings.menuBar.style == .combined && settings.menuBar.autoFitNotch {
                        Label("Notch fit active", systemImage: "laptopcomputer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Live, using your real stats. Hover an item to highlight it below, or click it to open its settings. Reordering below moves items in the menu bar and the deck.")
                    .settingsFooter()
            }

            Section("Style") {
                Picker("Show as", selection: $settings.menuBar.style) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .settingsAnchor("menuBar.style")

                Toggle("Show vibe ring", isOn: $settings.menuBar.showVibeRing)
                    .disabled(settings.menuBar.style == .ring)
                    .settingsAnchor("menuBar.ring")
                Toggle(isOn: $settings.menuBar.alwaysColorRing) {
                    Text("Always color the ring")
                    Text("Shows the vibe color even when everything's vibing.")
                }
                Toggle(isOn: $settings.menuBar.pulseOnNeedsInput) {
                    Text("Pulse the ring when an agent needs you")
                    Text("Reads hook files in ~/.config/vibecheck/hooks. See examples/hooks for how to write them.")
                }
            }

            AdvancedSection(id: "menuBar.advanced", title: "Layout & notch") {
                Picker("Spacing", selection: $settings.menuBar.spacing) {
                    ForEach(MenuBarSpacing.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .settingsAnchor("menuBar.spacing")

                Toggle("Colorful graphs", isOn: $settings.menuBar.colorful)

                Toggle(isOn: $settings.menuBar.autoFitNotch) {
                    Text("Fit around the camera notch")
                    Text("On a display with a notch, the combined item shows as many stats as fit beside it (in the order below) plus a +N badge. Everything stays in the deck.")
                }
                .disabled(settings.menuBar.style != .combined)
                .settingsAnchor("menuBar.notch")

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
                    ModuleRow(module: module, drag: itemDrag, hoveredModule: $hoveredModule)
                }
            } header: {
                Text("Items")
                    .settingsAnchor("menuBar.items")
            } footer: {
                Text("Drag to reorder, press ⌘↑ / ⌘↓ when focused, or right-click a row for Move Up / Move Down. Click › for an item's options and alerts.")
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

/// Aligned 4-column module row: drag handle + icon + title | fixed-width style picker | locked switch | chevron.
private struct ModuleRow: View {
    let module: Module
    let drag: ItemDrag
    @Binding var hoveredModule: Module?
    @Environment(AppSettings.self) private var settings
    @State private var rowHeight: CGFloat = 28
    @State private var hoveringHandle = false
    @State private var hoveringRow = false

    private var index: Int? { settings.moduleOrder.firstIndex(of: module) }
    private var isDragged: Bool { drag.isOver && drag.dragging == module }
    private var lineAbove: Bool { drag.gap != nil && drag.gap == index }
    private var lineBelow: Bool { drag.gap != nil && drag.gap == settings.moduleOrder.count && index == settings.moduleOrder.count - 1 }
    private var isSyncedHighlight: Bool { hoveredModule == module }

    var body: some View {
        let enabled = settings.isEnabled(module)
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hoveringHandle ? .secondary : .tertiary)
                .frame(width: 16, height: 24)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside, !hoveringHandle { NSCursor.openHand.push() }
                    else if !inside, hoveringHandle { NSCursor.pop() }
                    hoveringHandle = inside
                }
                .onDisappear {
                    if hoveringHandle { NSCursor.pop(); hoveringHandle = false }
                }
                .accessibilityHidden(true)

            SettingsIcon(symbol: module.symbol, color: module.accent, size: 20)
                .opacity(enabled ? 1 : 0.48)

            Text(module.title)
                .foregroundStyle(enabled ? .primary : .secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Picker("Display", selection: Binding(get: { settings.labelStyle(module) },
                                                 set: { settings.setLabelStyle($0, for: module) })) {
                ForEach(module.labelStyles) { Text($0.title(for: module)).tag($0) }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 158, alignment: .trailing)
            .disabled(!enabled)

            Toggle("Show \(module.title)", isOn: Binding(get: { enabled }, set: { settings.setEnabled(module, $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(enabled && settings.enabledModules.count == 1)

            Button {
                SettingsRouter.shared.open(.module(module))
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hoveringRow ? .secondary : .tertiary)
                    .frame(width: 18, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("\(module.title) settings")
            .accessibilityLabel("\(module.title) settings")
        }
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.accentColor.opacity(isSyncedHighlight ? 0.11 : 0))
                .padding(.horizontal, -6)
                .allowsHitTesting(false)
        )
        // Grouped Forms on macOS ignore .onMove (it only works in a List), so rows reorder by drag and drop.
        .contentShape(Rectangle())
        .onHover { inside in
            hoveringRow = inside
            if inside { hoveredModule = module }
            else if hoveredModule == module { hoveredModule = nil }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
        .opacity(isDragged ? 0.35 : 1)
        .overlay(alignment: .top) { insertionLine.opacity(lineAbove ? 1 : 0).offset(y: -5) }
        .overlay(alignment: .bottom) { insertionLine.opacity(lineBelow ? 1 : 0).offset(y: 5) }
        .animation(.easeOut(duration: 0.12), value: drag.gap)
        .animation(.easeOut(duration: 0.14), value: isSyncedHighlight)
        .onDrag {
            if hoveringHandle { NSCursor.pop(); hoveringHandle = false }
            drag.dragging = module
            return NSItemProvider(object: module.rawValue as NSString)
        } preview: {
            Label { Text(module.title) } icon: { SettingsIcon(symbol: module.symbol, color: module.accent, size: 18) }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .onDrop(of: [.plainText], delegate: ItemDropDelegate(module: module, rowHeight: rowHeight, settings: settings, drag: drag))
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.key == .upArrow { moveUp(); return .handled }
            if press.key == .downArrow { moveDown(); return .handled }
            return .ignored
        }
        .accessibilityAction(named: String(localized: "Move Up")) { moveUp() }
        .accessibilityAction(named: String(localized: "Move Down")) { moveDown() }
        .contextMenu {
            if let idx = index {
                Button("Move Up") { moveUp() }.disabled(idx == 0)
                Button("Move Down") { moveDown() }.disabled(idx == settings.moduleOrder.count - 1)
            }
            Divider()
            Button("\(module.title) Settings…") { SettingsRouter.shared.open(.module(module)) }
        }
    }

    private func moveUp() {
        guard let idx = index, idx > 0 else { return }
        withAnimation(.snappy(duration: 0.2)) { settings.moveModules(from: [idx], to: idx - 1) }
    }

    private func moveDown() {
        guard let idx = index, idx < settings.moduleOrder.count - 1 else { return }
        withAnimation(.snappy(duration: 0.2)) { settings.moveModules(from: [idx], to: idx + 2) }
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

/// Interactive preview wallpaper themes so users can test translucency and contrast over real backdrops.
private enum PreviewBackdrop: String, CaseIterable, Identifiable {
    case vivid, dark, light
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vivid: String(localized: "Vivid")
        case .dark: String(localized: "Dark")
        case .light: String(localized: "Light")
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .vivid:
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.24, blue: 0.56),
                    Color(red: 0.10, green: 0.50, blue: 0.64),
                    Color(red: 0.45, green: 0.22, blue: 0.66),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark:
            LinearGradient(
                colors: [Color(white: 0.08), Color(white: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .light:
            LinearGradient(
                colors: [Color(red: 0.86, green: 0.91, blue: 0.98), Color(red: 0.94, green: 0.88, blue: 0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

/// Interactive miniature Mac menu bar with wallpaper switcher, toggleable notch simulator, and hover-sync.
private struct MenuBarPreview: View {
    @Binding var hoveredModule: Module?
    @Environment(AppSettings.self) private var settings
    @Environment(SystemStats.self) private var stats
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var backdrop: PreviewBackdrop = .vivid
    @State private var previewNotch = true

    private var showNotch: Bool { previewNotch }

    private var simulatedVisibleCount: Int? {
        guard showNotch, settings.menuBar.style == .combined, settings.menuBar.autoFitNotch else { return nil }
        let total = settings.orderedModules.count
        let cap = settings.menuBar.notchMaxStats
        if cap > 0, cap < total { return cap }
        return total > 4 ? 4 : nil
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                backdrop.gradient
                    .frame(height: 54)
                    .overlay(alignment: .top) {
                        barStrip
                    }
                    .overlay(alignment: .topLeading) {
                        if showNotch {
                            notchSilhouette
                                .padding(.leading, 18)
                                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        }
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            .accessibilityLabel("Menu bar preview")

            HStack(spacing: 10) {
                Picker("Wallpaper", selection: $backdrop) {
                    ForEach(PreviewBackdrop.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 170)

                Spacer()

                Toggle("Preview MacBook notch", isOn: $previewNotch)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.82),
                   value: showNotch)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.84),
                   value: settings.orderedModules)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.84),
                   value: settings.menuBar.notchMaxStats)
    }

    private var barStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                if settings.menuBar.style == .combined {
                    interactiveCombined
                } else {
                    HStack(spacing: 10) {
                        if settings.menuBar.ringVisible { VibeItemLabel() }
                        if settings.menuBar.style != .ring {
                            ForEach(settings.orderedModules) { interactiveItem($0, padded: true) }
                        }
                    }
                }
                HStack(spacing: 12) {
                    Image(systemName: "wifi")
                    Image(systemName: "switch.2")
                    Text(Date(), format: .dateTime.weekday(.abbreviated).hour().minute())
                }
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            .frame(height: 28)
            .padding(.horizontal, 12)
        }
        .defaultScrollAnchor(.trailing)
        .mask(HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 24)
            Rectangle()
        })
        .padding(.leading, showNotch ? 92 : 0)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.separator.opacity(0.6)).frame(height: 0.5)
        }
    }

    private var interactiveCombined: some View {
        let all = settings.orderedModules
        let shown = simulatedVisibleCount.map { Array(all.prefix($0)) } ?? all
        return HStack(spacing: settings.menuBar.spacing.between) {
            if settings.menuBar.ringVisible {
                VibeRing(vibe: stats.vibe.vibe, awake: AwakeCup.inRing(settings)).frame(height: 22)
            }
            if AwakeCup.isShown(settings) { AwakeCup() }
            ForEach(shown) { interactiveItem($0, padded: false) }
            if shown.count < all.count {
                HiddenCountChip(count: all.count - shown.count)
            }
        }
        .padding(.horizontal, settings.menuBar.spacing.padding)
    }

    private func interactiveItem(_ module: Module, padded: Bool) -> some View {
        let isHovered = hoveredModule == module
        return Button {
            SettingsRouter.shared.open(.module(module))
        } label: {
            MenuBarLabel(module: module, padded: padded)
                .padding(.horizontal, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor.opacity(isHovered ? 0.24 : 0))
                )
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hoveredModule = module }
            else if hoveredModule == module { hoveredModule = nil }
        }
        .help("Open \(module.title) settings")
    }

    /// Minimal camera housing silhouette representing the MacBook notch boundary.
    private var notchSilhouette: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 7,
            bottomTrailingRadius: 7,
            topTrailingRadius: 0,
            style: .continuous
        )
        .fill(.black)
        .frame(width: 68, height: 22)
        .overlay(
            Circle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 5, height: 5)
        )
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var showingPermissions = false
    @State private var permissionItems: [PermissionItem] = []

    private var attentionCount: Int { PermissionsInspector.attentionCount(in: permissionItems) }

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .settingsAnchor("general.launchAtLogin")
            }

            Section {
                DeckGlassPreview()
                Toggle("Show quick toggles in the deck", isOn: $settings.showQuickToggles)
                    .settingsAnchor("general.quickToggles")
                Toggle("Show the summary card in the deck", isOn: $settings.showDeckSummary)
                LabeledContent("Popover opacity") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.deckOpacity, in: 0...1, step: 0.05)
                            .frame(width: 160)
                        Text("\(Int((settings.deckOpacity * 100).rounded()))%")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                .settingsAnchor("general.deckOpacity")
            } header: {
                Text("Deck")
            } footer: {
                Text("Popover opacity blends a solid surface over glass (0% is clear glass, 100% is solid). Quick toggles include mic mute, Bluetooth, Share Vibe Card, volume, and built-in display brightness.")
                    .settingsFooter()
            }

            ExplainSettingRow()

            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        if attentionCount > 0 {
                            Label("\(attentionCount) need attention", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                        } else {
                            Label("All clear", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        }
                        Button("Manage…") { showingPermissions = true }
                    }
                } label: {
                    Text("Permissions & Privacy")
                    Text("Calendar, Reminders, Bluetooth, Location, Accessibility, and Clipboard.")
                }
                .settingsAnchor("general.permissions")
            } header: {
                Text("Privacy")
            }

            Section {
                LabeledContent("Export your settings to a file") {
                    Button("Export…") { SettingsBackup.runExport() }
                }
                .settingsAnchor("general.backup")
                LabeledContent("Replace settings from a file") {
                    Button("Import…") { SettingsBackup.runImport() }
                }
                LabeledContent("Reset all settings to defaults") {
                    Button("Reset…", role: .destructive) { SettingsBackup.runReset() }
                }
            } header: {
                Text("Backup & Reset")
            } footer: {
                Text("Reset restores defaults and restarts VibeCheck. History graphs and logs are kept.")
                    .settingsFooter()
            }

            AdvancedSection(id: "general.advanced", title: "Sampling") {
                Picker("Update every", selection: $settings.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
                .settingsAnchor("general.refreshInterval")
            }
        }
        .settingsForm()
        .onAppear { permissionItems = PermissionsInspector.snapshot() }
        .sheet(isPresented: $showingPermissions, onDismiss: { permissionItems = PermissionsInspector.snapshot() }) {
            PermissionsSheet()
        }
    }
}

/// Live miniature Deck card showing popover opacity, Quick Toggles, and Summary card over switchable backdrops.
private struct DeckGlassPreview: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SystemStats.self) private var stats
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var backdrop: PreviewBackdrop = .vivid

    private var opacityBadge: String {
        if reduceTransparency { return String(localized: "Opaque (Reduce Transparency)") }
        let pct = Int((settings.deckOpacity * 100).rounded())
        if pct == 0 { return String(localized: "Clear Glass · 0%") }
        if pct == 100 { return String(localized: "Solid · 100%") }
        return String(localized: "Frosted · \(pct)%")
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                backdrop.gradient
                    .overlay(
                        Circle()
                            .fill(Color.mint.opacity(backdrop == .vivid ? 0.42 : 0.16))
                            .frame(width: 130, height: 130)
                            .blur(radius: 26)
                            .offset(x: -100, y: -20)
                    )
                    .overlay(
                        Circle()
                            .fill(Color.blue.opacity(backdrop == .vivid ? 0.35 : 0.14))
                            .frame(width: 140, height: 140)
                            .blur(radius: 28)
                            .offset(x: 110, y: 24)
                    )

                // Miniature Deck popover card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        VibeRing(vibe: stats.vibe.vibe, awake: KeepAwake.shared.isActive)
                            .frame(width: 20, height: 20)
                        Text(stats.vibe.vibe.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Spacer()
                        Text("CPU \(Int(stats.cpu.total.rounded()))%")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if settings.showQuickToggles {
                        HStack(spacing: 6) {
                            ForEach(["mic.fill", "dot.radiowaves.left.and.right", "speaker.wave.2.fill", "sun.max.fill"], id: \.self) { symbol in
                                Image(systemName: symbol)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 22)
                                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.primary.opacity(0.08)))
                            }
                        }
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
                    }

                    if settings.showDeckSummary {
                        HStack(spacing: 6) {
                            Circle().fill(Color.mint).frame(width: 5, height: 5)
                            Text(stats.vibe.verdict)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.primary.opacity(0.06)))
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
                    }
                }
                .padding(12)
                .frame(maxWidth: 340)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
                    ZStack {
                        if reduceTransparency {
                            shape.fill(.windowBackground)
                        } else {
                            shape.fill(.ultraThinMaterial)
                            shape.fill(.windowBackground.opacity(settings.deckOpacity))
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))

            HStack {
                Picker("Wallpaper", selection: $backdrop) {
                    ForEach(PreviewBackdrop.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 170)

                Spacer()

                Text(opacityBadge)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.84),
                   value: settings.showQuickToggles)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.84),
                   value: settings.showDeckSummary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reduceTransparency
            ? String(localized: "Deck preview, opaque because Reduce Transparency is enabled")
            : String(localized: "Deck preview at \(Int((settings.deckOpacity * 100).rounded())) percent opacity"))
    }
}

/// "On-device explanations": shown only when the system model is usable, or disabled with a reason when fixable.
private struct ExplainSettingRow: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        switch OnDeviceExplainer.toggleState(for: OnDeviceExplainer.availability()) {
        case .hidden:
            EmptyView()
        case .enabled:
            Section {
                Toggle("On-device explanations", isOn: $settings.onDeviceExplanations)
                    .settingsAnchor("general.explanations")
            } footer: {
                Text("Uses Apple's on-device model. Nothing leaves your Mac.").settingsFooter()
            }
        case .disabled(let reason):
            Section {
                Toggle("On-device explanations", isOn: .constant(false)).disabled(true)
                    .settingsAnchor("general.explanations")
            } footer: {
                Text(reason).settingsFooter()
            }
        }
    }
}

// MARK: - About & Support

private struct AboutSettings: View {
    @Environment(AppSettings.self) private var settings
    private var updates = UpdateChecker.shared
    /// The command whose Copy button was just pressed, so it can say "Copied" for a moment.
    @State private var copied: String?

    private static let licenseURL = URL(string: "https://github.com/saroj-shahi/vibecheck/blob/main/LICENSE")!
    private static let githubURL = URL(string: "https://github.com/saroj-shahi/vibecheck")!
    private static let coffeeURL = URL(string: "https://buymeacoffee.com/sarojshahi")!

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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.10"
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
                        .frame(width: 88, height: 88)
                        .accessibilityHidden(true)
                    HStack(spacing: 0) {
                        Text("Vibe")
                        Text("Check")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.24, green: 0.88, blue: 0.71),
                                        Color(red: 0.21, green: 0.71, blue: 0.95),
                                        Color(red: 0.55, green: 0.42, blue: 1.0),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                    Text("Mac health in one ring").foregroundStyle(.secondary)
                    Text("Version \(version) · © 2026 Saroj Shahi")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Link("Free software under GPL-3.0, no warranty", destination: Self.licenseURL)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
                    .settingsAnchor("about.updates")
                LabeledContent("Look for a newer version now") {
                    HStack(spacing: 8) {
                        if updates.state == .checking { ProgressView().controlSize(.small) }
                        Button("Check Now") { Task { await updates.check() } }
                            .disabled(updates.state == .checking)
                    }
                }
                updateStatus
            }

            Section("Support") {
                HStack(spacing: 14) {
                    SettingsIcon(symbol: "heart.fill", color: .pink, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enjoying VibeCheck?").fontWeight(.medium)
                        Text("Free, open source, no ads or tracking. A coffee or a GitHub star keeps it going.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button("GitHub") { NSWorkspace.shared.open(Self.githubURL) }
                    Button {
                        NSWorkspace.shared.open(Self.coffeeURL)
                    } label: {
                        Label("Buy Me a Coffee", systemImage: "mug.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding(.vertical, 4)
                .settingsAnchor("about.support")
            }

            AdvancedSection(id: "about.shortcuts", title: "Getting around") {
                LabeledContent("Check the vibes", value: "Click the menu bar item")
                LabeledContent("Open a module from anywhere", value: "\(settings.hotkeyModifier.symbols)1–9, 0")
                LabeledContent("Find anything in the deck", value: "⌘K")
                LabeledContent("Open Settings from the deck", value: "⌘,")
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
                    .settingsAnchor("shortcuts.global")
                Picker("Modifier keys", selection: $settings.hotkeyModifier) {
                    ForEach(HotkeyModifier.allCases) { Text($0.symbols).tag($0) }
                }
                .disabled(!settings.hotkeysEnabled)
            }

            Section {
                Toggle("\(settings.hotkeyModifier.symbols)A starts or stops Keep Awake", isOn: $settings.keepAwake.hotkey)
                Toggle("\(settings.hotkeyModifier.symbols)V opens clipboard history", isOn: $settings.clipboardHotkey)
                Toggle("\(settings.hotkeyModifier.symbols)F finds your cursor", isOn: $settings.findCursorHotkey)
                Toggle("\(settings.hotkeyModifier.symbols)J joins the next video call", isOn: $settings.joinCallHotkey)
            } header: {
                Text("Quick actions")
            } footer: {
                Text("Press a shortcut from any app to trigger or toggle that tool.")
                    .settingsFooter()
            }
            .disabled(!settings.hotkeysEnabled)

            AdvancedSection(id: "shortcuts.modules", title: "Module shortcuts (1–9, 0)") {
                ForEach(Module.allCases) { module in
                    HStack {
                        Label(module.title, systemImage: module.symbol)
                            .foregroundStyle(settings.isEnabled(module) ? .primary : .secondary)
                        Spacer()
                        Text(module.shortcutKey.map { "\(settings.hotkeyModifier.symbols)\($0)" } ?? "—")
                            .font(.body.monospaced())
                            .foregroundStyle(settings.isEnabled(module) ? .primary : .tertiary)
                    }
                }
                .settingsAnchor("shortcuts.modules")
                Text("Press a module shortcut from any app to open that panel; press it again to close. Shortcuts for switched-off modules just beep.")
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

/// Always-expanded grouped section for advanced or secondary options (never hidden behind a disclosure).
struct AdvancedSection<Content: View>: View {
    var id: String = "advanced"
    var title: LocalizedStringKey = "Advanced"
    @ViewBuilder var content: Content

    var body: some View {
        Section(title) {
            content
        }
    }
}

extension View {
    /// Every Settings page: spacious native grouped form with calm horizontal and vertical breathing room.
    func settingsForm() -> some View {
        formStyle(.grouped)
            .contentMargins(.vertical, 14, for: .scrollContent)
            .padding(.horizontal, 18)
            .environment(\.defaultMinListRowHeight, 40)
    }

    /// Form section footer: legible 11 pt secondary text, leading-aligned.
    func settingsFooter() -> some View {
        font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
