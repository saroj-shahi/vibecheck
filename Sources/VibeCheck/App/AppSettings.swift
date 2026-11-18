import Foundation
import Observation
import ServiceManagement
import SwiftUI

enum Module: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, network, disk, sensors, battery, clock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .network: "Network"
        case .disk: "Disk"
        case .sensors: "Sensors"
        case .battery: "Battery"
        case .clock: "Clock"
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
        }
    }

    /// Width of the menu bar item for a style, in points (the clock is measured separately).
    func labelWidth(_ style: LabelStyle) -> CGFloat {
        switch (self, style) {
        case (.cpu, .standard), (.gpu, .standard): 60
        case (.memory, .standard): 50
        case (.cpu, _), (.gpu, _), (.memory, _): style == .iconAndValue ? 52 : 34
        case (.network, .standard), (.disk, .standard): 64
        case (.network, .iconAndValue), (.disk, .iconAndValue): 64
        case (.network, _), (.disk, _): 46
        case (.sensors, .valueOnly): 32
        case (.sensors, _): 50
        case (.battery, .valueOnly): 38
        case (.battery, _): 54
        case (.clock, _): 80
        }
    }

    var labelStyles: [LabelStyle] {
        switch self {
        case .sensors, .battery: [.standard, .valueOnly]
        case .clock: [.standard, .iconAndValue]
        default: LabelStyle.allCases
        }
    }

    var enabledByDefault: Bool { self != .battery && self != .clock }
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
    var id: String { rawValue }

    func title(for module: Module) -> String {
        switch self {
        case .standard:
            switch module {
            case .cpu, .gpu: "Graph + value"
            case .memory: "Gauge + value"
            case .network: "Rates + arrows"
            case .disk: "Rates + R/W"
            case .sensors, .battery: "Icon + value"
            case .clock: "Time only"
            }
        case .iconAndValue: module == .clock ? "Icon + time" : "Icon + value"
        case .valueOnly: "Value only"
        }
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case separate, combined
    var id: String { rawValue }
    var title: String { self == .separate ? "Separate items" : "One combined item" }
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
    private let defaults = UserDefaults.standard

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
    var hotkeyModifier: HotkeyModifier {
        didSet { save(hotkeyModifier.rawValue, "hotkeyModifier", structural: true) }
    }
    var alertRules: [AlertRule] {
        didSet {
            if let data = try? JSONEncoder().encode(alertRules) { defaults.set(data, forKey: "alertRules") }
        }
    }
    private(set) var labelStyles: [Module: LabelStyle]
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

    private init() {
        let stored = defaults.array(forKey: "enabledModules") as? [String]
        var enabled = stored.map { Set($0.compactMap(Module.init(rawValue:))) }
            ?? Set(Module.allCases.filter(\.enabledByDefault))
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
        menuBarStyle = defaults.string(forKey: "menuBarStyle").flatMap(MenuBarStyle.init(rawValue:)) ?? .separate
        hotkeysEnabled = defaults.object(forKey: "hotkeysEnabled") as? Bool ?? true
        hotkeyModifier = defaults.string(forKey: "hotkeyModifier").flatMap(HotkeyModifier.init(rawValue:))
            ?? .controlOptionCommand
        let storedStyles = defaults.dictionary(forKey: "labelStyles") as? [String: String] ?? [:]
        labelStyles = storedStyles.reduce(into: [:]) { result, entry in
            if let module = Module(rawValue: entry.key), let style = LabelStyle(rawValue: entry.value) {
                result[module] = style
            }
        }
        colorfulMenuBar = defaults.object(forKey: "colorfulMenuBar") as? Bool ?? true
        clockFormat = defaults.string(forKey: "clockFormat").flatMap(ClockFormat.init(rawValue:)) ?? .dayTime
        clockShowSeconds = defaults.bool(forKey: "clockShowSeconds")
        worldClocks = defaults.data(forKey: "worldClocks")
            .flatMap { try? JSONDecoder().decode([WorldClock].self, from: $0) } ?? WorldClock.defaults
        alertRules = defaults.data(forKey: "alertRules")
            .flatMap { try? JSONDecoder().decode([AlertRule].self, from: $0) } ?? AlertRule.defaults
    }

    func labelStyle(_ module: Module) -> LabelStyle {
        let style = labelStyles[module] ?? .standard
        return module.labelStyles.contains(style) ? style : .standard
    }

    func setLabelStyle(_ style: LabelStyle, for module: Module) {
        labelStyles[module] = style
        defaults.set(Dictionary(uniqueKeysWithValues: labelStyles.map { ($0.key.rawValue, $0.value.rawValue) }),
                     forKey: "labelStyles")
        NotificationCenter.default.post(name: .vibeCheckSettingsChanged, object: nil)
    }

    var clockFormatStyle: ClockFormatStyle { ClockFormatStyle(format: clockFormat, seconds: clockShowSeconds) }

    /// Menu bar width for a module in its current style. The clock is measured from a worst-case date string.
    func labelWidth(_ module: Module) -> CGFloat {
        let style = labelStyle(module)
        guard module == .clock else { return module.labelWidth(style) }
        let widest = DateComponents(calendar: .current, year: 2026, month: 9, day: 30, hour: 22, minute: 58, second: 58).date ?? Date()
        let text = clockFormat.formatter(seconds: clockShowSeconds).string(from: widest)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(width) + (style == .iconAndValue ? 22 : 6)
    }

    /// Modules that are switched on, in menu bar order.
    var orderedModules: [Module] { Module.allCases.filter(enabledModules.contains) }

    private func save(_ value: Any, _ key: String, structural: Bool) {
        defaults.set(value, forKey: key)
        if structural { NotificationCenter.default.post(name: .vibeCheckSettingsChanged, object: nil) }
    }

    func isEnabled(_ module: Module) -> Bool { enabledModules.contains(module) }

    func setEnabled(_ module: Module, _ enabled: Bool) {
        if enabled { enabledModules.insert(module) } else {
            guard enabledModules.count > 1 else { return } // always keep one item to click
            enabledModules.remove(module)
        }
        defaults.set(enabledModules.map(\.rawValue), forKey: "enabledModules")
        NotificationCenter.default.post(name: .vibeCheckSettingsChanged, object: nil)
    }
}
