import Testing
import Foundation
@testable import VibeCheck

struct SleepDrainTests {
    static let log = """
    2026-11-20 02:10:00 +0545 Sleep               \tEntering Sleep state due to 'Clamshell Sleep':TCPKeepAlive=active Using Batt (Charge:80%) 41 secs
    2026-11-20 02:40:11 +0545 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to EC.ARPT/Network Using BATT (Charge:79%) 6 secs
    2026-11-20 02:40:11 +0545 WakeDetails         \tDriverReason:smc.sysState.Wake(0x70070000) - DriverDetails:
    2026-11-20 02:40:12 +0545 Wake Requests       \t[*process=dasd request=SleepService deltaSecs=983 wakeAt=2026-11-20 02:56:00]
    2026-11-20 03:10:20 +0545 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty/ Using BATT (Charge:78%) 6 secs
    2026-11-20 04:10:20 +0545 DarkWake            \tDarkWake from Normal Sleep [CDNP] : due to RTC/Maintenance Using BATT (Charge:77%) 30 secs
    2026-11-20 05:00:00 +0545 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to NUB.SPMI0Sw3IRQ nub-spmi0.0x02 Using BATT (Charge:76%) 6 secs
    2026-11-19 12:00:00 +0545 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to EC.ARPT/Network Using BATT (Charge:90%) 6 secs
    2026-11-20 09:00:00 +0545 Wake                \tWake from Deep Idle [CDNVA] : due to smc.sysState.Wake(0x70070000) pwrbtn SMC.OutboxNotEmpty/UserActivity Assertion Using BATT (Charge:73%)
    """

    static func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f.date(from: s)!
    }

    @Test func parsesOnlyWindowAndTalliesReasons() {
        let s = SleepDrain.parse(log: Self.log, from: Self.date("2026-11-20 02:10:00 +0545"),
                                 to: Self.date("2026-11-20 08:59:55 +0545"))
        #expect(s.wakes == 4)
        #expect(s.causes["Wi-Fi"] == 1)
        #expect(s.causes["Wi-Fi or Bluetooth"] == 1)
        #expect(s.causes["scheduled maintenance"] == 1)
        #expect(s.causes["other"] == 1)
        #expect(s.causes.values.max() == 1)
    }

    @Test func emptyLogGivesNoCauses() {
        let s = SleepDrain.parse(log: "", from: Date(timeIntervalSince1970: 0), to: Date())
        #expect(s == SleepDrain.WakeSummary())
    }

    @Test func reasonWords() {
        #expect(SleepDrain.plainReason("smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty/") == "Wi-Fi or Bluetooth")
        #expect(SleepDrain.plainReason("smc.sysState.Wake(0x70070000) pwrbtn SMC.OutboxNotEmpty/UserActivity Assertion") == "the power button")
        #expect(SleepDrain.plainReason("RTC/Maintenance") == "scheduled maintenance")
        #expect(SleepDrain.plainReason("UserActivity Assertion") == "you")
        #expect(SleepDrain.plainReason("EC.ARPT/Network") == "Wi-Fi")
        #expect(SleepDrain.plainReason("EC.LID0") == "the lid")
        #expect(SleepDrain.plainReason("XHC1 usb") == "a USB device")
        #expect(SleepDrain.plainReason("Bluetooth HID") == "Bluetooth")
        #expect(SleepDrain.plainReason("NUB.SPMI0Sw3IRQ nub-spmi0.0x02") == "other")
    }

    @Test func evaluateThresholds() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        func m(_ p: Double, _ b: Bool, _ h: Double) -> SleepDrain.Mark { .init(percent: p, onBattery: b, date: t.addingTimeInterval(h * 3600)) }
        #expect(SleepDrain.evaluate(start: m(0.8, true, 0), end: m(0.68, true, 8))?.drop == 12)
        #expect(SleepDrain.evaluate(start: m(0.8, true, 0), end: m(0.68, true, 8))?.hours == 8)
        #expect(SleepDrain.evaluate(start: m(0.8, true, 0), end: m(0.68, true, 1.5)) == nil)
        #expect(SleepDrain.evaluate(start: m(0.8, true, 0), end: m(0.77, true, 8)) == nil)
        #expect(SleepDrain.evaluate(start: m(0.8, false, 0), end: m(0.68, true, 8)) == nil)
        #expect(SleepDrain.evaluate(start: m(0.8, true, 0), end: m(0.68, false, 8)) == nil)
    }

    @Test func textAndExpiry() {
        var r = SleepDrain.Report(drop: 9, hours: 7, summary: .init(), created: Date())
        #expect(SleepDrain.text(for: r) == "Overnight: battery dropped 9% in 7 h.")
        r.summary = .init(wakes: 23, causes: ["Wi-Fi": 15, "other": 8])
        #expect(SleepDrain.text(for: r) == "Overnight: battery dropped 9% in 7 h. It woke 23 times, mostly for Wi-Fi.")
        #expect(!SleepDrain.isExpired(r, now: Date()))
        #expect(SleepDrain.isExpired(r, now: Date().addingTimeInterval(13 * 3600)))
    }

    @Test func firstMarkIsKept() {
        let a = SleepDrain.Mark(percent: 0.8, onBattery: true, date: Date(timeIntervalSince1970: 100))
        let b = SleepDrain.Mark(percent: 0.7, onBattery: true, date: Date(timeIntervalSince1970: 200))
        #expect(SleepDrain.keepFirst(a, { b }) == a)
        #expect(SleepDrain.keepFirst(nil, { b }) == b)
    }
}
