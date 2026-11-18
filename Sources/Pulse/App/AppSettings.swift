import Foundation
import Observation
import ServiceManagement
import SwiftUI

enum Module: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, network, disk, sensors, battery

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
        }
    }

    /// Width of the menu bar item, in points.
    var labelWidth: CGFloat {
        switch self {
        case .cpu: 60
        case .gpu: 60
        case .memory: 50
        case .network: 64
        case .disk: 64
        case .sensors: 50
        case .battery: 54
        }
    }

    var enabledByDefault: Bool { self != .battery }
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
    static let pulseSettingsChanged = Notification.Name("PulseSettingsChanged")
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
            NotificationCenter.default.post(name: .pulseSettingsChanged, object: nil)
        }
    }
    var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Pulse: launch-at-login change failed: \(error.localizedDescription)")
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
    }

    func isEnabled(_ module: Module) -> Bool { enabledModules.contains(module) }

    func setEnabled(_ module: Module, _ enabled: Bool) {
        if enabled { enabledModules.insert(module) } else {
            guard enabledModules.count > 1 else { return } // always keep one item to click
            enabledModules.remove(module)
        }
        defaults.set(enabledModules.map(\.rawValue), forKey: "enabledModules")
        NotificationCenter.default.post(name: .pulseSettingsChanged, object: nil)
    }
}
