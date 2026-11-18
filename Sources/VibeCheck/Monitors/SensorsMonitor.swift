import Foundation
import IOKit

struct TemperatureReading: Identifiable {
    var id: String { name }
    let name: String
    let celsius: Double
}

struct FanReading: Identifiable {
    let id: Int
    let rpm: Double
    let minRPM: Double?
    let maxRPM: Double?

    /// Position of the current speed between min and max, 0...1 (0 when the fan is off).
    var level: Double {
        guard rpm > 0, let maxRPM, maxRPM > 0 else { return 0 }
        let floor = minRPM ?? 0
        return min(1, max(0, (rpm - floor) / max(maxRPM - floor, 1)))
    }
}

struct SensorsSample {
    /// Friendly summary groups, e.g. "CPU / SoC (hottest)", "SSD", "Battery".
    var summary: [TemperatureReading] = []
    /// Every raw sensor, for the "All sensors" list.
    var all: [TemperatureReading] = []
    var fans: [FanReading] = []
    var systemPower: Double?    // watts, whole machine
    var adapterPower: Double?   // watts drawn from the charger

    /// The number shown in the menu bar.
    var hottest: Double? { summary.first?.celsius }
}

/// Temperatures from the HID sensor hub (Apple Silicon) with SMC fallbacks (Intel), plus fans and power from the SMC.
final class SensorsMonitor {
    private let hid = HIDTemperatureSensors()
    private let smc = SMC()

    func sample() -> SensorsSample {
        var result = SensorsSample()
        let raw = hid?.read() ?? []
        result.all = raw.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        func group(_ label: String, where match: (String) -> Bool, useMax: Bool) {
            let values = raw.filter { match($0.name) }.map(\.celsius)
            guard !values.isEmpty else { return }
            let value = useMax ? values.max()! : values.reduce(0, +) / Double(values.count)
            result.summary.append(TemperatureReading(name: label, celsius: value))
        }
        group("CPU / SoC (hottest)", where: { $0.contains("tdie") }, useMax: true)
        group("CPU / SoC (average)", where: { $0.contains("tdie") }, useMax: false)
        group("SSD", where: { $0.hasPrefix("NAND") }, useMax: true)
        group("Battery", where: { $0.hasPrefix("gas gauge") }, useMax: false)

        if let smc {
            if result.summary.isEmpty { // Intel Macs: well-known SMC temperature keys
                let keys = [("CPU", "TC0P"), ("CPU die", "TC0D"), ("GPU", "TG0P"), ("Battery", "TB0T")]
                for (label, key) in keys {
                    if let t = smc.value(key), (1...130).contains(t) {
                        result.summary.append(TemperatureReading(name: label, celsius: t))
                    }
                }
                result.summary.sort { $0.celsius > $1.celsius }
                if result.all.isEmpty { result.all = result.summary }
            }

            let fanCount = Int(smc.value("FNum") ?? 0)
            result.fans = (0..<min(fanCount, 4)).compactMap { i in
                guard let rpm = smc.value("F\(i)Ac") else { return nil }
                return FanReading(id: i, rpm: max(0, rpm),
                                  minRPM: smc.value("F\(i)Mn"), maxRPM: smc.value("F\(i)Mx"))
            }
            result.systemPower = smc.value("PSTR").flatMap { $0 > 0 ? $0 : nil }
            result.adapterPower = smc.value("PDTR").flatMap { $0 > 0 ? $0 : nil }
        }
        return result
    }
}

/// Wraps the private IOHIDEventSystemClient API that Apple Silicon uses for its temperature sensors.
/// Symbols are looked up at runtime so a future macOS that removes them degrades to "no sensors" instead of crashing.
private final class HIDTemperatureSensors {
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatching = @convention(c) (CFTypeRef, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEvent = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias GetFloat = @convention(c) (CFTypeRef, Int32) -> Double

    private static let temperatureEvent: Int64 = 15            // kIOHIDEventTypeTemperature
    private static let temperatureField: Int32 = 15 << 16      // kIOHIDEventFieldTemperatureLevel

    private let copyEvent: CopyEvent
    private let getFloat: GetFloat
    private let services: [(name: String, service: CFTypeRef)]
    private let client: CFTypeRef

    init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return nil }
        func symbol<T>(_ name: String, _ type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let create = symbol("IOHIDEventSystemClientCreate", Create.self),
              let setMatching = symbol("IOHIDEventSystemClientSetMatching", SetMatching.self),
              let copyServices = symbol("IOHIDEventSystemClientCopyServices", CopyServices.self),
              let copyProperty = symbol("IOHIDServiceClientCopyProperty", CopyProperty.self),
              let copyEvent = symbol("IOHIDServiceClientCopyEvent", CopyEvent.self),
              let getFloat = symbol("IOHIDEventGetFloatValue", GetFloat.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }

        // Vendor usage page 0xff00, usage 5 = temperature sensors.
        _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        let list = copyServices(client)?.takeRetainedValue() as? [CFTypeRef] ?? []
        guard !list.isEmpty else { return nil }

        self.client = client
        self.copyEvent = copyEvent
        self.getFloat = getFloat
        self.services = list.map { service in
            let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String ?? "Sensor"
            return (name, service)
        }
    }

    func read() -> [TemperatureReading] {
        var readings: [TemperatureReading] = []
        var seen: [String: Int] = [:]
        for (name, service) in services {
            guard let event = copyEvent(service, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { continue }
            let value = getFloat(event, Self.temperatureField)
            guard (1...130).contains(value) else { continue } // drop uncalibrated/garbage channels
            // Several sensors share a name (e.g. "gas gauge battery"); number the repeats.
            let count = seen[name, default: 0] + 1
            seen[name] = count
            readings.append(TemperatureReading(name: count > 1 ? "\(name) \(count)" : name, celsius: value))
        }
        return readings
    }
}
