import Foundation
import IOKit
import IOKit.ps

struct BatterySample {
    var present = false
    var percent: Double = 0
    var isCharging = false
    var onAC = true
    var isCharged = false
    var minutesRemaining: Int?   // to empty when discharging, to full when charging
    var cycleCount: Int?
    var health: Double?          // max capacity / design capacity
    var temperature: Double?     // °C
    var powerWatts: Double?      // positive = charging, negative = draining
    var condition: String?
}

enum BatteryMonitor {
    static func sample() -> BatterySample {
        var result = BatterySample()

        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                      desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                result.present = true
                let current = desc[kIOPSCurrentCapacityKey] as? Double ?? 0
                let max = desc[kIOPSMaxCapacityKey] as? Double ?? 100
                result.percent = max > 0 ? current / max : 0
                result.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
                result.isCharged = desc[kIOPSIsChargedKey] as? Bool ?? false
                result.onAC = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
                let minutes = result.isCharging ? desc[kIOPSTimeToFullChargeKey] as? Int
                                                : desc[kIOPSTimeToEmptyKey] as? Int
                if let minutes, minutes > 0 { result.minutesRemaining = minutes }
                result.condition = desc[kIOPSBatteryHealthKey] as? String
            }
        }
        guard result.present else { return result }

        // Extra detail from the smart battery controller.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return result }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let top = props?.takeRetainedValue() as? [String: Any] else { return result }

        // Newer macOS versions move capacity details into a nested "BatteryData" dictionary.
        let nested = top["BatteryData"] as? [String: Any] ?? [:]
        func number(_ key: String) -> NSNumber? { (top[key] ?? nested[key]) as? NSNumber }

        result.cycleCount = number("CycleCount")?.intValue
        if let percent = number("MaximumCapacityPercent")?.doubleValue, percent > 0 {
            result.health = percent / 100
        } else if let design = number("DesignCapacity")?.doubleValue, design > 0,
                  let rawMax = (number("NominalChargeCapacity") ?? number("AppleRawMaxCapacity"))?.doubleValue {
            result.health = min(1.2, rawMax / design)
        }
        if let temp = (number("Temperature") ?? number("VirtualTemperature"))?.doubleValue, temp > 0 {
            result.temperature = temp / 100
        }
        let dict = top
        if let volts = (dict["Voltage"] as? NSNumber)?.doubleValue,
           let amps = (dict["Amperage"] as? NSNumber)?.int64Value {
            result.powerWatts = volts * Double(amps) / 1_000_000
        }
        return result
    }
}
