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
