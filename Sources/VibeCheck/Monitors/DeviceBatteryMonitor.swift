import Foundation
import IOKit

struct DeviceBattery: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let kind: String?            // "Mouse", "Keyboard", "Headset", ...
    /// One or more levels, e.g. [("", 80)] or [("L", 90), ("R", 85), ("Case", 40)]. Empty if unknown.
    var levels: [(label: String, percent: Int)]

    var lowest: Int? { levels.map(\.percent).min() }

    var symbol: String {
        switch kind?.lowercased() ?? "" {
        case let k where k.contains("mouse"): "computermouse"
        case let k where k.contains("keyboard"): "keyboard"
        case let k where k.contains("trackpad"): "rectangle.and.hand.point.up.left"
        case let k where k.contains("headset") || k.contains("headphone"): "headphones"
        default:
            name.localizedCaseInsensitiveContains("airpods") ? "airpodspro" : "dot.radiowaves.left.and.right"
        }
    }
}

/// Battery levels of connected Bluetooth accessories (Apple keyboards/mice/trackpads, AirPods and other
/// headsets that report it). Third-party devices often don't expose a level; they're listed without one.
enum DeviceBatteryMonitor {
    static func fetch() async -> [DeviceBattery] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: read())
            }
        }
    }

    private static func read() -> [DeviceBattery] {
        var devices: [String: DeviceBattery] = [:]
        for device in profilerDevices() { devices[device.name] = device }
        // HID services carry live levels for Apple input devices; prefer them when present.
        for device in hidDevices() {
            if var existing = devices[device.name], !device.levels.isEmpty {
                existing.levels = device.levels
                devices[device.name] = existing
            } else if devices[device.name] == nil {
                devices[device.name] = device
            }
        }
        return devices.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func hidDevices() -> [DeviceBattery] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [DeviceBattery] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard let percent = (property("BatteryPercent") as? NSNumber)?.intValue,
                  let name = property("Product") as? String,
                  !name.localizedCaseInsensitiveContains("internal") else { continue }
            let kind = ["Keyboard", "Mouse", "Trackpad"].first { name.localizedCaseInsensitiveContains($0) }
            result.append(DeviceBattery(name: name, kind: kind, levels: [("", percent)]))
        }
        return result
    }

    private static func profilerDevices() -> [DeviceBattery] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controller = (json["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = controller["device_connected"] as? [[String: Any]] else { return [] }

        let labelled = [("device_batteryLevelMain", ""), ("device_batteryLevel", ""),
                        ("device_batteryLevelLeft", "L"), ("device_batteryLevelRight", "R"),
                        ("device_batteryLevelCase", "Case")]
        return connected.flatMap { entry in
            entry.compactMap { name, value -> DeviceBattery? in
                guard let props = value as? [String: Any] else { return nil }
                let levels = labelled.compactMap { key, label -> (String, Int)? in
                    guard let text = props[key] as? String,
                          let percent = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) else { return nil }
                    return (label, percent)
                }
                return DeviceBattery(name: name.trimmingCharacters(in: .whitespaces),
                                     kind: props["device_minorType"] as? String, levels: levels)
            }
        }
    }
}
