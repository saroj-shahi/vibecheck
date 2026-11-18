import Foundation
import Testing
@testable import VibeCheck

@MainActor
struct AccessoryAlertTests {
    private func device(_ name: String, _ levels: [Int]) -> DeviceBattery {
        DeviceBattery(name: name, kind: nil, levels: levels.map { ("", $0) })
    }

    @Test func lowestDeviceWins() {
        let result = AlertEngine.lowestAccessory(in: [device("Mouse", [64]), device("MX Keys", [18]), device("Pods", [90, 55])])
        #expect(result?.name == "MX Keys")
        #expect(result?.percent == 18)
    }

    @Test func devicesWithoutBatteryAreIgnored() {
        let result = AlertEngine.lowestAccessory(in: [device("Speaker", []), device("Mouse", [40])])
        #expect(result?.name == "Mouse")
        #expect(AlertEngine.lowestAccessory(in: [device("Speaker", [])]) == nil)
    }

    @Test func nilWithNoDevices() {
        #expect(AlertEngine.lowestAccessory(in: []) == nil)
    }

    @Test func messageNamesTheDevice() {
        let rule = AlertRule(metric: .accessoryBattery, comparison: .below, threshold: 20, duration: 0)
        #expect(rule.describe(current: 18, detail: "MX Keys") == "Accessory battery has been below 20%. MX Keys is at 18%.")
        #expect(rule.describe(current: 18).hasSuffix("Now 18%."))
    }

    @Test func engineDeliversDeviceName() {
        let engine = AlertEngine()
        var sent: [String] = []
        engine.deliver = { _, body in sent.append(body) }
        let rule = AlertRule(metric: .accessoryBattery, comparison: .below, threshold: 20, duration: 0)
        engine.evaluate([rule], detail: { _ in "MX Keys" }, value: { _ in 18 })
        #expect(sent == ["Accessory battery has been below 20%. MX Keys is at 18%."])
    }
}

struct DeviceSamplingTests {
    @Test func devicesAreReadOnlyWhenSomethingShowsThem() {
        let alert = AlertRule(metric: .accessoryBattery, comparison: .below, threshold: 20, duration: 0)
        var off = alert; off.enabled = false
        #expect(SystemStats.needsDevices(batteryOn: true, rules: []))
        #expect(SystemStats.needsDevices(batteryOn: false, rules: [alert]))
        #expect(!SystemStats.needsDevices(batteryOn: false, rules: [off]))
        #expect(!SystemStats.needsDevices(batteryOn: false, rules: AlertRule.defaults))
    }
}
