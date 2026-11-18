import Foundation
import IOKit.pwr_mgt
import Testing
@testable import VibeCheck

struct KeepAwakeTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var onAC: BatterySample { var b = BatterySample(); b.present = true; b.onAC = true; b.percent = 0.05; return b }
    var onBattery: BatterySample { var b = BatterySample(); b.present = true; b.onAC = false; b.percent = 0.15; return b }

    @Test func timedSessionEndsAtItsTime() {
        let session = AwakeSession(started: now, end: AwakePreset.end(30, from: now))
        let check = { (date: Date) in
            AwakeSession.endReason(session, now: date, battery: BatterySample(), batteryFloor: 0) { _ in true }
        }
        #expect(check(now.addingTimeInterval(29 * 60)) == nil)
        #expect(check(now.addingTimeInterval(30 * 60)) == .timeUp)
        #expect(AwakePreset.end(0, from: now) == .never)
    }

    @Test func appSessionEndsWhenTheAppQuits() {
        let session = AwakeSession(started: now, end: .whileRunning(bundleID: "com.apple.Safari", name: "Safari"))
        #expect(AwakeSession.endReason(session, now: now, battery: BatterySample(), batteryFloor: 0) { $0 == "com.apple.Safari" } == nil)
        #expect(AwakeSession.endReason(session, now: now, battery: BatterySample(), batteryFloor: 0) { _ in false } == .appQuit)
    }

    @Test func batteryFloorOnlyCountsOnBattery() {
        let session = AwakeSession(started: now, end: .never)
        #expect(AwakeSession.endReason(session, now: now, battery: onBattery, batteryFloor: 20) { _ in true } == .lowBattery)
        #expect(AwakeSession.endReason(session, now: now, battery: onBattery, batteryFloor: 10) { _ in true } == nil)
        #expect(AwakeSession.endReason(session, now: now, battery: onBattery, batteryFloor: 0) { _ in true } == nil)
        #expect(AwakeSession.endReason(session, now: now, battery: onAC, batteryFloor: 20) { _ in true } == nil)
    }

    @Test func remainingReadsNaturally() {
        func left(_ minutes: Double) -> String {
            AwakeSession(started: now, end: .at(now.addingTimeInterval(minutes * 60))).remaining(now: now)
        }
        #expect(left(30) == "30 min left")
        #expect(left(0.2) == "1 min left")
        #expect(left(60) == "1 h left")
        #expect(left(125) == "2 h 5 min left")
        #expect(AwakeSession(started: now, end: .never).remaining(now: now) == "until you stop it")
        #expect(AwakeSession(started: now, end: .whileRunning(bundleID: "x", name: "Xcode")).remaining(now: now) == "until Xcode quits")
        #expect(AwakePreset.title(0) == "Indefinitely")
        #expect(AwakePreset.title(60) == "1 hour")
        #expect(AwakePreset.title(300) == "5 hours")
    }

    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    @Test func untilTimeRollsOverToTomorrow() {
        let at1430 = Date(timeIntervalSince1970: 1_800_023_400) // 14:30 UTC (1_800_000_000 is 08:00)
        let six = AwakePreset.nextOccurrence(ofMinute: 18 * 60, after: at1430, calendar: utc)
        #expect(six.timeIntervalSince(at1430) == 3.5 * 3600)
        let nine = AwakePreset.nextOccurrence(ofMinute: 9 * 60, after: at1430, calendar: utc)
        #expect(nine.timeIntervalSince(at1430) == 18.5 * 3600)
        let hours = AwakePreset.upcomingHours(after: at1430, count: 3, calendar: utc)
        #expect(hours.map { $0.timeIntervalSince(at1430) / 60 } == [30, 90, 150])
        let at1450 = at1430.addingTimeInterval(20 * 60) // under 15 minutes to 15:00, so start at 16:00
        #expect(AwakePreset.upcomingHours(after: at1450, count: 1, calendar: utc).first?.timeIntervalSince(at1450) == Double(70 * 60))
    }

    @Test func triggersAreEdgeTriggered() {
        let manual = AwakeSession(started: now, end: .never)
        let triggered = AwakeSession(started: now, end: .whileTriggered("while plugged in"))
        #expect(AwakeTriggerAction.decide(active: "while plugged in", wasActive: false, session: nil) == .start("while plugged in"))
        #expect(AwakeTriggerAction.decide(active: "while plugged in", wasActive: true, session: nil) == .none) // stopped by hand
        #expect(AwakeTriggerAction.decide(active: "while plugged in", wasActive: false, session: manual) == .none) // manual wins
        #expect(AwakeTriggerAction.decide(active: nil, wasActive: true, session: triggered) == .stop)
        #expect(AwakeTriggerAction.decide(active: nil, wasActive: true, session: manual) == .none)
        #expect(AwakeTriggerAction.description(onPower: true, externalDisplay: false) == "while plugged in")
        #expect(AwakeTriggerAction.description(onPower: true, externalDisplay: true) == "while plugged in and a display is connected")
        #expect(AwakeTriggerAction.description(onPower: false, externalDisplay: false) == nil)
        #expect(triggered.remaining(now: now) == "while plugged in")
        #expect(AwakeSession.endReason(triggered, now: now, battery: onBattery, batteryFloor: 0) { _ in true } == nil)
        #expect(!AwakeEndReason.triggerOff.notifies && AwakeEndReason.timeUp.notifies)
    }

    /// Starts a real session and checks that macOS lists VibeCheck's assertion, then that stopping releases it.
    @MainActor @Test func realAssertionIsHeldAndReleased() {
        func ours() -> [String] {
            var unmanaged: Unmanaged<CFDictionary>?
            guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
                  let byPid = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]],
                  let mine = byPid[NSNumber(value: getpid())] else { return [] }
            return mine.filter { $0[kIOPMAssertionNameKey] as? String == "VibeCheck keep awake" }
                .compactMap { $0[kIOPMAssertionTypeKey] as? String }
        }
        let awake = KeepAwake.shared
        awake.stop()
        #expect(ours().isEmpty)
        awake.start(minutes: 15)
        #expect(awake.isActive)
        #expect(ours().count == 1)
        awake.stop()
        #expect(!awake.isActive)
        #expect(ours().isEmpty)
    }
}
