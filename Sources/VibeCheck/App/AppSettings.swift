import Foundation
import Observation
import ServiceManagement
import SwiftUI

enum Module: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, network, disk, sensors, battery, clock, weather, agents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: String(localized: "CPU")
        case .gpu: String(localized: "GPU")
        case .memory: String(localized: "Memory")
        case .network: String(localized: "Network")
        case .disk: String(localized: "Disk")
        case .sensors: String(localized: "Sensors")
        case .battery: String(localized: "Battery")
        case .clock: String(localized: "Clock")
        case .weather: String(localized: "Weather")
        case .agents: String(localized: "Agents")
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "cube"
        case .memory: "memorychip"
        case .network: "network"
        case .disk: "internaldrive"
        case .sensors: "thermometer.medium"
        case .battery: "battery.75percent"
        case .clock: "clock"
        case .weather: "cloud.sun"
        case .agents: "sparkles"
        }
    }

    var accent: Color {
        switch self {
        case .cpu: Palette.user
        case .gpu: Palette.gpu
        case .memory: Palette.app
        case .network: Palette.download
        case .disk: Palette.read
        case .sensors: .orange
        case .battery: .green
        case .clock: .indigo
        case .weather: .cyan
        case .agents: Palette.agents
        }
    }

    var labelStyles: [LabelStyle] {
        switch self {
        case .sensors, .battery, .weather: [.standard, .valueOnly]
        case .agents: [.standard, .valueOnly]
        case .clock: [.standard, .iconAndValue]
        default: [.standard, .iconAndValue, .valueOnly]
        }
    }

    var enabledByDefault: Bool { ![.battery, .clock, .weather].contains(self) }

    /// Tiles a brand-new install starts with (six, in the fixed module order). Existing installs keep their saved set.
    var enabledForNewInstall: Bool { [.cpu, .memory, .network, .sensors, .battery, .agents].contains(self) }

    /// Number key for ⌘N in the deck and the global shortcuts: 1–9, then 0 for the tenth module.
    var shortcutKey: String? {
        guard let index = Module.allCases.firstIndex(of: self), index < 10 else { return nil }
        return index == 9 ? "0" : String(index + 1)
    }

    static func forShortcutKey(_ key: String) -> Module? { allCases.first { $0.shortcutKey == key } }
}

enum Palette {
    static let user = Color(red: 0.25, green: 0.56, blue: 1.0)
    static let system = Color(red: 1.0, green: 0.33, blue: 0.33)
    static let gpu = Color(red: 0.55, green: 0.85, blue: 0.3)
    static let tiler = Color(red: 0.95, green: 0.75, blue: 0.25)
    static let app = Color(red: 0.36, green: 0.6, blue: 1.0)
    static let wired = Color(red: 1.0, green: 0.62, blue: 0.2)
    static let compressed = Color(red: 0.72, green: 0.45, blue: 1.0)
    static let cached = Color.gray.opacity(0.55)
    static let download = Color(red: 0.2, green: 0.78, blue: 0.75)
    static let upload = Color(red: 1.0, green: 0.4, blue: 0.62)
    static let read = Color(red: 0.35, green: 0.75, blue: 0.4)
    static let write = Color(red: 1.0, green: 0.7, blue: 0.2)
    static let agents = Color(red: 0.85, green: 0.5, blue: 0.95)

    static func pressure(_ p: MemoryPressure) -> Color {
        switch p {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }

    static func temperature(_ celsius: Double) -> Color {
        celsius >= 90 ? .red : celsius >= 75 ? .orange : celsius >= 55 ? .yellow : .green
    }

    static func level(_ fraction: Double) -> Color {
        fraction > 0.85 ? .red : fraction > 0.65 ? .orange : .green
    }
}

extension Notification.Name {
    static let vibeCheckSettingsChanged = Notification.Name("VibeCheckSettingsChanged")
}

/// How a single item draws itself in the menu bar.
enum LabelStyle: String, CaseIterable, Identifiable {
    case standard, iconAndValue, valueOnly
    /// Agents only: two stacked rows, "% left" and time to reset for the 5-hour and weekly limits.
    case limits
    var id: String { rawValue }

    func title(for module: Module) -> String {
        switch self {
        case .standard:
            switch module {
            case .cpu, .gpu: String(localized: "Graph + value")
            case .memory: String(localized: "Gauge + value")
            case .network: String(localized: "Rates + arrows")
            case .disk: String(localized: "Rates + R/W")
            case .sensors, .battery, .weather, .agents: String(localized: "Icon + value")
            case .clock: String(localized: "Time only")
            }
        case .iconAndValue: module == .clock ? String(localized: "Icon + time") : String(localized: "Icon + value")
        case .valueOnly: String(localized: "Value only")
        case .limits: String(localized: "Limits left")
        }
    }
}

/// How tightly menu bar content is packed.
enum MenuBarSpacing: String, CaseIterable, Identifiable {
    case normal, compact, tight
    var id: String { rawValue }
    var title: String { switch self { case .normal: String(localized: "Normal"); case .compact: String(localized: "Compact"); case .tight: String(localized: "Tight") } }
    /// Gap between an item's icon/graph and its value.
    var inner: CGFloat { switch self { case .normal: 4; case .compact: 2; case .tight: 1 } }
    /// Empty space on each side of an item.
    var padding: CGFloat { switch self { case .normal: 4; case .compact: 2; case .tight: 0 } }
    /// Gap between modules inside the combined item.
    var between: CGFloat { switch self { case .normal: 8; case .compact: 4; case .tight: 2 } }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case ring, separate, combined
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ring: String(localized: "Just the vibe ring")
        case .separate: String(localized: "Separate items")
        case .combined: String(localized: "One combined item")
        }
    }
}

/// Modifier combination for the global shortcuts; the key is the module's number (1 = CPU, 2 = GPU, ...).
enum HotkeyModifier: String, CaseIterable, Identifiable {
    case controlOptionCommand, controlOption, optionCommand
    var id: String { rawValue }
    var symbols: String {
        switch self {
        case .controlOptionCommand: "⌃⌥⌘"
        case .controlOption: "⌃⌥"
        case .optionCommand: "⌥⌘"
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()
    private let defaults: UserDefaults

    private(set) var enabledModules: Set<Module>
    var refreshInterval: Double {
        didSet {
            defaults.set(refreshInterval, forKey: "refreshInterval")
            NotificationCenter.default.post(name: .vibeCheckSettingsChanged, object: nil)
        }
    }
    var menuBarStyle: MenuBarStyle {
        didSet { save(menuBarStyle.rawValue, "menuBarStyle", structural: true) }
    }
    var hotkeysEnabled: Bool {
        didSet { save(hotkeysEnabled, "hotkeysEnabled", structural: true) }
    }
    /// Opt-in: look up the public IP address (contacts api.ipify.org).
    var showPublicIP: Bool {
        didSet { save(showPublicIP, "showPublicIP", structural: false) }
    }
    var hotkeyModifier: HotkeyModifier {
        didSet { save(hotkeyModifier.rawValue, "hotkeyModifier", structural: true) }
    }
    var alertRules: [AlertRule] {
        didSet {
            if let data = try? JSONEncoder().encode(alertRules) { defaults.set(data, forKey: "alertRules") }
        }
    }
    private(set) var labelStyles: [Module: LabelStyle]
    /// Per-item options beyond the look (which agents, % left or used, memory amount, …).
    private(set) var itemOptions: [Module: ItemOptions] = [:]
    /// User-chosen order for the combined item, the deck grid and (on creation) separate items.
    private(set) var moduleOrder: [Module]
    var menuBarSpacing: MenuBarSpacing {
        didSet { save(menuBarSpacing.rawValue, "menuBarSpacing", structural: true) }
    }
    var autoFitNotch: Bool {
        didSet { save(autoFitNotch, "autoFitNotch", structural: true) }
    }
    /// At most this many stats beside the notch (0 = as many as fit).
    var notchMaxStats: Int {
        didSet { save(notchMaxStats, "notchMaxStats", structural: true) }
    }
    /// Notch auto-collapse state (per Mac, not part of backups): the one-time notice was shown; VibeCheck
    /// switched to the combined item by itself; the owner switched back to separate items, so don't again.
    var notchNoticeShown: Bool {
        didSet { save(notchNoticeShown, "notchNoticeShown", structural: false) }
    }
    var notchAutoCollapsed: Bool {
        didSet { save(notchAutoCollapsed, "notchAutoCollapsed", structural: false) }
    }
    var notchCollapseOptOut: Bool {
        didSet { save(notchCollapseOptOut, "notchCollapseOptOut", structural: false) }
    }
    /// The ring is drawn when it's on, and always in the ring-only style.
    var ringVisible: Bool { showVibeRing || menuBarStyle == .ring }
    var showVibeRing: Bool {
        didSet { save(showVibeRing, "showVibeRing", structural: true) }
    }
    var colorfulMenuBar: Bool {
        didSet { save(colorfulMenuBar, "colorfulMenuBar", structural: false) }
    }
    var clockFormat: ClockFormat {
        didSet { save(clockFormat.rawValue, "clockFormat", structural: true) }
    }
    var clockShowSeconds: Bool {
        didSet { save(clockShowSeconds, "clockShowSeconds", structural: true) }
    }
    var worldClocks: [WorldClock] {
        didSet {
            if let data = try? JSONEncoder().encode(worldClocks) { defaults.set(data, forKey: "worldClocks") }
        }
    }
    var weatherLocation: WeatherLocation? {
        didSet {
            defaults.set(weatherLocation.flatMap { try? JSONEncoder().encode($0) }, forKey: "weatherLocation")
            WeatherStore.shared.refresh()
        }
    }
    var temperatureUnit: TemperatureUnit {
        didSet {
            defaults.set(temperatureUnit.rawValue, forKey: "temperatureUnit")
            WeatherStore.shared.refresh()
        }
    }

    /// Keep awake: length of a quick-start session in minutes (0 = indefinitely).
    var keepAwakeDefaultMinutes: Int {
        didSet { save(keepAwakeDefaultMinutes, "keepAwakeDefaultMinutes", structural: false) }
    }
    /// Keep the display on too; off lets the screen sleep while the Mac stays awake.
    var keepAwakeDisplayOn: Bool {
        didSet { save(keepAwakeDisplayOn, "keepAwakeDisplayOn", structural: false); KeepAwake.shared.check() }
    }
    /// End a session when on battery below this percent (0 = never).
    var keepAwakeBatteryFloor: Int {
        didSet { save(keepAwakeBatteryFloor, "keepAwakeBatteryFloor", structural: false); KeepAwake.shared.check() }
    }
    var keepAwakeAtLaunch: Bool {
        didSet { save(keepAwakeAtLaunch, "keepAwakeAtLaunch", structural: false) }
    }
    /// Time of day for "until" sessions started from Settings, in minutes after midnight.
    var keepAwakeUntilMinute: Int {
        didSet { save(keepAwakeUntilMinute, "keepAwakeUntilMinute", structural: false) }
    }
    /// Notify when a session ends by itself.
    var keepAwakeNotify: Bool {
        didSet { save(keepAwakeNotify, "keepAwakeNotify", structural: false) }
    }
    /// Global shortcut (modifier + A) that starts or stops a session.
    var keepAwakeHotkey: Bool {
        didSet { save(keepAwakeHotkey, "keepAwakeHotkey", structural: true) }
    }
    /// Triggers: stay awake automatically while plugged in / while an external display is connected.
    var keepAwakeOnPower: Bool {
        didSet { save(keepAwakeOnPower, "keepAwakeOnPower", structural: false); KeepAwake.shared.check() }
    }
    var keepAwakeWithDisplay: Bool {
        didSet { save(keepAwakeWithDisplay, "keepAwakeWithDisplay", structural: false); KeepAwake.shared.check() }
    }
    /// Trigger: stay awake while files are arriving in `downloadsFolderURL` (`DownloadsWatcher`).
    var keepAwakeWhileDownloading: Bool {
        didSet {
            save(keepAwakeWhileDownloading, "keepAwakeWhileDownloading", structural: false)
            DownloadsWatcher.shared.reset()
            KeepAwake.shared.check()
        }
    }
    /// Trigger: stay awake inside a weekly window (`keepAwakeSchedule`).
    var keepAwakeOnSchedule: Bool {
        didSet { save(keepAwakeOnSchedule, "keepAwakeOnSchedule", structural: false); KeepAwake.shared.check() }
    }
    /// Trigger: stay awake while an AI agent writes to its logs (`AgentWatch`).
    var keepAwakeWhileAgentWorks: Bool {
        didSet {
            save(keepAwakeWhileAgentWorks, "keepAwakeWhileAgentWorks", structural: false)
            AgentUsageStore.shared.refresh()
            KeepAwake.shared.check()
        }
    }
    /// Call guard: while the camera or mic is in use, hold non-critical alerts, keep the display awake and
    /// warn about one heavy app.
    var callGuardEnabled: Bool {
        didSet { save(callGuardEnabled, "callGuardEnabled", structural: false); KeepAwake.shared.check() }
    }
    /// Trigger: stay awake while connected to the Wi-Fi network named in `keepAwakeWiFiName`.
    /// Asks for Location permission when switched on (macOS hides network names without it).
    var keepAwakeWhileOnWiFi: Bool {
        didSet {
            save(keepAwakeWhileOnWiFi, "keepAwakeWhileOnWiFi", structural: false)
            if keepAwakeWhileOnWiFi { WiFiTrigger.shared.requestAccess() }
            KeepAwake.shared.check()
        }
    }
    var keepAwakeWiFiName: String {
        didSet { save(keepAwakeWiFiName, "keepAwakeWiFiName", structural: false); KeepAwake.shared.check() }
    }
    /// Notify when an agent finishes a run of 10 minutes or more.
    var notifyAgentFinished: Bool {
        didSet { save(notifyAgentFinished, "notifyAgentFinished", structural: false); AgentUsageStore.shared.refresh() }
    }
    var keepAwakeScheduleDays: Int {
        didSet { save(keepAwakeScheduleDays, "keepAwakeScheduleDays", structural: false); KeepAwake.shared.check() }
    }
    var keepAwakeScheduleStart: Int {
        didSet { save(keepAwakeScheduleStart, "keepAwakeScheduleStart", structural: false); KeepAwake.shared.check() }
    }
    var keepAwakeScheduleEnd: Int {
        didSet { save(keepAwakeScheduleEnd, "keepAwakeScheduleEnd", structural: false); KeepAwake.shared.check() }
    }
    var keepAwakeSchedule: AwakeSchedule {
        AwakeSchedule(days: keepAwakeScheduleDays, startMinute: keepAwakeScheduleStart, endMinute: keepAwakeScheduleEnd)
    }
    /// Folder the downloads trigger watches; empty means the user's Downloads folder.
    var keepAwakeDownloadsFolder: String {
        didSet {
            save(keepAwakeDownloadsFolder, "keepAwakeDownloadsFolder", structural: false)
            DownloadsWatcher.shared.reset()
            KeepAwake.shared.check()
        }
    }
    var downloadsFolderURL: URL {
        keepAwakeDownloadsFolder.isEmpty ? DownloadsWatcher.defaultFolder
            : URL(fileURLWithPath: keepAwakeDownloadsFolder, isDirectory: true)
    }
    /// Turn Bluetooth off while the Mac sleeps, back on at wake (`BluetoothSnooze`).
    var bluetoothOffWhileAsleep: Bool {
        didSet {
            save(bluetoothOffWhileAsleep, "bluetoothOffWhileAsleep", structural: false)
            if bluetoothOffWhileAsleep { BluetoothSnooze.shared.requestAccess() }
        }
    }
    /// Show a cup in the menu bar while a session runs.
    var keepAwakeShowInMenuBar: Bool {
        didSet { save(keepAwakeShowInMenuBar, "keepAwakeShowInMenuBar", structural: true) }
    }
    /// A standalone Keep Awake item in the menu bar (always visible). Click toggles, right-click shows a menu.
    var keepAwakeMenuBarItem: Bool {
        didSet { save(keepAwakeMenuBarItem, "keepAwakeMenuBarItem", structural: true) }
    }

    /// While the clock panel is open its seconds tick even if the menu bar shows minutes only.
    @ObservationIgnored var isClockPanelOpen = false

    var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("VibeCheck: launch-at-login change failed: \(error.localizedDescription)")
            }
        }
    }

    private convenience init() { self.init(defaults: .standard) }

    /// Internal so tests can use a throwaway suite.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        let stored = defaults.array(forKey: "enabledModules") as? [String]
        var enabled = stored.map { Set($0.compactMap(Module.init(rawValue:))) }
            ?? Set(Module.allCases.filter(\.enabledForNewInstall))
        // Modules added in a newer version show up once if they're on by default.
        // Before "knownModules" existed (v1.0), every module except GPU and Sensors had shipped.
        let known = (defaults.array(forKey: "knownModules") as? [String])
            .map { Set($0.compactMap(Module.init(rawValue:))) }
            ?? Set(Module.allCases).subtracting([.gpu, .sensors])
        if stored != nil {
            enabled.formUnion(Module.allCases.filter { $0.enabledByDefault && !known.contains($0) })
        }
        enabledModules = enabled
        defaults.set(Module.allCases.map(\.rawValue), forKey: "knownModules")
        defaults.set(enabled.map(\.rawValue), forKey: "enabledModules")
        let interval = defaults.double(forKey: "refreshInterval")
        refreshInterval = interval > 0 ? interval : 2
        launchAtLogin = SMAppService.mainApp.status == .enabled
        // New installs start with just the vibe ring (the deck has everything else); an existing install
        // (it had saved its modules) without a stored choice keeps the combined item.
        menuBarStyle = defaults.string(forKey: "menuBarStyle").flatMap(MenuBarStyle.init(rawValue:))
            ?? (stored == nil ? .ring : .combined)
        hotkeysEnabled = defaults.object(forKey: "hotkeysEnabled") as? Bool ?? true
        showPublicIP = defaults.object(forKey: "showPublicIP") as? Bool ?? false
        hotkeyModifier = defaults.string(forKey: "hotkeyModifier").flatMap(HotkeyModifier.init(rawValue:))
            ?? .controlOptionCommand
        let storedOrder = (defaults.array(forKey: "moduleOrder") as? [String] ?? []).compactMap(Module.init(rawValue:))
        moduleOrder = Self.completeOrder(storedOrder)
        let storedStyles = defaults.dictionary(forKey: "labelStyles") as? [String: String] ?? [:]
        labelStyles = storedStyles.reduce(into: [:]) { result, entry in
            if let module = Module(rawValue: entry.key), let style = LabelStyle(rawValue: entry.value) {
                result[module] = style
            }
        }
        let storedOptions = defaults.data(forKey: "itemOptions")
            .flatMap { try? JSONDecoder().decode([String: ItemOptions].self, from: $0) } ?? [:]
        itemOptions = storedOptions.reduce(into: [:]) { result, entry in
            if let module = Module(rawValue: entry.key) { result[module] = entry.value }
        }
        menuBarSpacing = defaults.string(forKey: "menuBarSpacing").flatMap(MenuBarSpacing.init(rawValue:)) ?? .normal
        autoFitNotch = defaults.object(forKey: "autoFitNotch") as? Bool ?? true
        notchMaxStats = defaults.integer(forKey: "notchMaxStats")
        notchNoticeShown = defaults.bool(forKey: "notchNoticeShown")
        notchAutoCollapsed = defaults.bool(forKey: "notchAutoCollapsed")
        notchCollapseOptOut = defaults.bool(forKey: "notchCollapseOptOut")
        showVibeRing = defaults.object(forKey: "showVibeRing") as? Bool ?? true
        colorfulMenuBar = defaults.object(forKey: "colorfulMenuBar") as? Bool ?? true
        clockFormat = defaults.string(forKey: "clockFormat").flatMap(ClockFormat.init(rawValue:)) ?? .dayTime
        clockShowSeconds = defaults.bool(forKey: "clockShowSeconds")
        worldClocks = defaults.data(forKey: "worldClocks")
            .flatMap { try? JSONDecoder().decode([WorldClock].self, from: $0) } ?? WorldClock.defaults
        weatherLocation = defaults.data(forKey: "weatherLocation")
            .flatMap { try? JSONDecoder().decode(WeatherLocation.self, from: $0) }
        temperatureUnit = defaults.string(forKey: "temperatureUnit").flatMap(TemperatureUnit.init(rawValue:))
            ?? (Locale.current.measurementSystem == .us ? .fahrenheit : .celsius)
        keepAwakeDefaultMinutes = defaults.object(forKey: "keepAwakeDefaultMinutes") as? Int ?? 0
        keepAwakeDisplayOn = defaults.object(forKey: "keepAwakeDisplayOn") as? Bool ?? true
        keepAwakeBatteryFloor = defaults.object(forKey: "keepAwakeBatteryFloor") as? Int ?? 10
        keepAwakeAtLaunch = defaults.bool(forKey: "keepAwakeAtLaunch")
        keepAwakeShowInMenuBar = defaults.object(forKey: "keepAwakeShowInMenuBar") as? Bool ?? true
        keepAwakeMenuBarItem = defaults.bool(forKey: "keepAwakeMenuBarItem")
        keepAwakeUntilMinute = defaults.object(forKey: "keepAwakeUntilMinute") as? Int ?? 18 * 60
        keepAwakeNotify = defaults.object(forKey: "keepAwakeNotify") as? Bool ?? true
        keepAwakeHotkey = defaults.object(forKey: "keepAwakeHotkey") as? Bool ?? true
        keepAwakeOnPower = defaults.bool(forKey: "keepAwakeOnPower")
        keepAwakeWithDisplay = defaults.bool(forKey: "keepAwakeWithDisplay")
        keepAwakeWhileDownloading = defaults.bool(forKey: "keepAwakeWhileDownloading")
        keepAwakeDownloadsFolder = defaults.string(forKey: "keepAwakeDownloadsFolder") ?? ""
        keepAwakeOnSchedule = defaults.bool(forKey: "keepAwakeOnSchedule")
        keepAwakeWhileAgentWorks = defaults.bool(forKey: "keepAwakeWhileAgentWorks")
        notifyAgentFinished = defaults.bool(forKey: "notifyAgentFinished")
        callGuardEnabled = defaults.object(forKey: "callGuardEnabled") as? Bool ?? true
        keepAwakeWhileOnWiFi = defaults.bool(forKey: "keepAwakeWhileOnWiFi")
        keepAwakeWiFiName = defaults.string(forKey: "keepAwakeWiFiName") ?? ""
        keepAwakeScheduleDays = defaults.object(forKey: "keepAwakeScheduleDays") as? Int ?? AwakeSchedule.weekdays
        keepAwakeScheduleStart = defaults.object(forKey: "keepAwakeScheduleStart") as? Int ?? 9 * 60
        keepAwakeScheduleEnd = defaults.object(forKey: "keepAwakeScheduleEnd") as? Int ?? 17 * 60
        bluetoothOffWhileAsleep = defaults.bool(forKey: "bluetoothOffWhileAsleep")
        alertRules = defaults.data(forKey: "alertRules")
            .flatMap { try? JSONDecoder().decode([AlertRule].self, from: $0) } ?? AlertRule.defaults
        // The old "Limits left" look is now an Agents option.
        if labelStyles[.agents] == .limits {
            labelStyles[.agents] = .standard
            var agents = itemOptions[.agents] ?? ItemOptions()
            agents.agentValue = .limitsLeft
            itemOptions[.agents] = agents
            defaults.set(Dictionary(uniqueKeysWithValues: labelStyles.map { ($0.key.rawValue, $0.value.rawValue) }),
                         forKey: "labelStyles")
            saveItemOptions()
        }
    }

    func labelStyle(_ module: Module) -> LabelStyle {
        let style = labelStyles[module] ?? .standard
        return module.labelStyles.contains(style) ? style : .standard
    }

    func options(_ module: Module) -> ItemOptions { itemOptions[module] ?? ItemOptions() }

    /// Changes one item's options; the item is re-measured (its width can change).
    func updateOptions(_ module: Module, _ change: (inout ItemOptions) -> Void) {
        var value = options(module)
        change(&value)
        guard value != options(module) else { return }
        itemOptions[module] = value
        saveItemOptions()
        NotificationCenter.default.post(name: .vibeCheckSettingsChanged, object: nil)
    }

    private func saveItemOptions() {
        let stored = Dictionary(uniqueKeysWithValues: itemOptions.map { ($0.key.rawValue, $0.value) })
        defaults.set(try? JSONEncoder().encode(stored), forKey: "itemOptions")
    }

    func setLabelStyle(_ style: LabelStyle, for module: Module) {
        labelStyles[module] = style
        defaults.set(Dictionary(uniqueKeysWithValues: labelStyles.map { ($0.key.rawValue, $0.value.rawValue) }),
                     forKey: "labelStyles")
        NotificationCenter.default.post(name: .vibeCheckSettingsChanged, object: nil)
    }

    var clockFormatStyle: ClockFormatStyle { ClockFormatStyle(format: clockFormat, seconds: clockShowSeconds) }

    /// Width that fits the clock's widest possible text in the current format, so it never jiggles.
    var clockTextWidth: CGFloat {
        let widest = DateComponents(calendar: .current, year: 2026, month: 9, day: 30, hour: 22, minute: 58, second: 58).date ?? Date()
        let text = clockFormat.formatter(seconds: clockShowSeconds).string(from: widest)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width) + 2
    }

    /// Modules that are switched on, in the user's order.
    var orderedModules: [Module] { moduleOrder.filter(enabledModules.contains) }

    /// Keeps the stored order and appends any module it doesn't mention (e.g. added in an update).
    nonisolated static func completeOrder(_ stored: [Module]) -> [Module] {
        var seen = Set<Module>()
        let unique = stored.filter { seen.insert($0).inserted }
        return unique + Module.allCases.filter { !seen.contains($0) }
    }

    func moveModules(from source: IndexSet, to destination: Int) {
        let before = moduleOrder
        moduleOrder.move(fromOffsets: source, toOffset: destination)
        defaults.set(moduleOrder.map(\.rawValue), forKey: "moduleOrder")
        // macOS keeps each separate item where it last was (by autosave name), so a new order needs new names.
        if moduleOrder != before { statusItemGeneration += 1 }
        NotificationCenter.default.post(name: .vibeCheckSettingsChanged, object: nil)
    }

    /// Bumped on every reorder; part of the separate items' autosave names (0 = the original names).
    var statusItemGeneration: Int {
        get { defaults.integer(forKey: "statusItemGeneration") }
        set { defaults.set(newValue, forKey: "statusItemGeneration") }
    }

    /// Autosave name for a status item. macOS remembers positions by this name; new names are placed
    /// in creation order, each to the left of the items already there.
    nonisolated static func autosaveName(_ base: String, generation: Int) -> String {
        generation > 0 ? "vibecheck.\(base).g\(generation)" : "vibecheck.\(base)"
    }

    private func save(_ value: Any, _ key: String, structural: Bool) {
        defaults.set(value, forKey: key)
        if structural { NotificationCenter.default.post(name: .vibeCheckSettingsChanged, object: nil) }
    }

    func isEnabled(_ module: Module) -> Bool { enabledModules.contains(module) }
    /// Whether the module's number is in the menu bar (its own item or the combined one). "Just the vibe ring"
    /// draws no module numbers, so the ring badge must name the culprit there.
    func showsInMenuBar(_ module: Module) -> Bool { menuBarStyle != .ring && isEnabled(module) }

    func setEnabled(_ module: Module, _ enabled: Bool) {
        if enabled { enabledModules.insert(module) } else {
            guard enabledModules.count > 1 else { return } // always keep one item to click
            enabledModules.remove(module)
        }
        defaults.set(enabledModules.map(\.rawValue), forKey: "enabledModules")
        NotificationCenter.default.post(name: .vibeCheckSettingsChanged, object: nil)
        if module == .weather { WeatherStore.shared.refresh() }
        if module == .agents { AgentUsageStore.shared.refresh() }
    }
}
