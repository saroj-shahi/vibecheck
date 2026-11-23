import Foundation
import Testing
@testable import VibeCheck

@MainActor
struct TickPolicyTests {
    @Test func runsAtBaseIntervalNormally() {
        #expect(TickPolicy.interval(base: 2, reasons: [], lowPower: false, keepAwakeSession: false) == 2)
    }

    @Test func lowPowerDoublesWithFourSecondMinimum() {
        #expect(TickPolicy.interval(base: 1, reasons: [], lowPower: true, keepAwakeSession: false) == 4)
        #expect(TickPolicy.interval(base: 5, reasons: [], lowPower: true, keepAwakeSession: false) == 10)
    }

    @Test func anyReasonStopsTheTick() {
        for reason in TickSuspendReason.allCases {
            #expect(TickPolicy.interval(base: 2, reasons: [reason], lowPower: false, keepAwakeSession: false) == nil)
        }
        #expect(TickPolicy.interval(base: 2, reasons: [.displayAsleep, .screenLocked], lowPower: true, keepAwakeSession: false) == nil)
    }

    @Test func keepAwakeSessionKeepsASlowTick() {
        #expect(TickPolicy.interval(base: 2, reasons: [.screenLocked], lowPower: false, keepAwakeSession: true) == 30)
        #expect(TickPolicy.interval(base: 60, reasons: [.screenLocked], lowPower: false, keepAwakeSession: true) == 60)
    }

    @Test func alwaysColorRingDefaultsOffAndIsBackedUp() {
        #expect(SettingsBackup.keys.contains("alwaysColorRing"))
        let group = MenuBarGroup(defaults: UserDefaults(suiteName: "TickPolicyTests-\(UUID().uuidString)")!, isNewInstall: false)
        #expect(group.alwaysColorRing == false)
    }
}
