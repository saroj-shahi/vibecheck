import Testing
@testable import VibeCheck

struct ChargerWattsTests {
    @Test func normal() { #expect(BatteryMonitor.adapterWatts(from: ["Watts": 67]) == 67) }
    @Test func missing() {
        #expect(BatteryMonitor.adapterWatts(from: ["Name": "x"]) == nil)
        #expect(BatteryMonitor.adapterWatts(from: nil) == nil)
    }
    @Test func zero() { #expect(BatteryMonitor.adapterWatts(from: ["Watts": 0]) == nil) }
    @Test func nonNumber() {
        #expect(BatteryMonitor.adapterWatts(from: ["Watts": "67"]) == nil)
        #expect(BatteryMonitor.adapterWatts(from: ["Watts": true]) == nil)
    }
    @Test func slow() {
        var b = BatterySample(); b.onAC = true; b.chargerWatts = 20; b.powerWatts = -5
        #expect(BatteryMonitor.isChargingSlowly(b))
        b.powerWatts = 5; #expect(!BatteryMonitor.isChargingSlowly(b))
        b.powerWatts = -5; b.chargerWatts = 67; #expect(!BatteryMonitor.isChargingSlowly(b))
        b.chargerWatts = 20; b.onAC = false; #expect(!BatteryMonitor.isChargingSlowly(b))
    }
}
