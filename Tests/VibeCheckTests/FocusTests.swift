import Foundation
import Testing
@testable import VibeCheck

struct FocusTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func focusEndsWithFocusDoneAndPlainTimersWithTimeUp() {
        let end = now.addingTimeInterval(-1)
        let focus = AwakeSession(started: now.addingTimeInterval(-1500), end: .at(end), focus: true)
        let plain = AwakeSession(started: now.addingTimeInterval(-1500), end: .at(end))
        func reason(_ s: AwakeSession) -> AwakeEndReason? {
            AwakeSession.endReason(s, now: now, battery: BatterySample(), batteryFloor: 0, isRunning: { _ in true })
        }
        #expect(reason(focus) == .focusDone)
        #expect(reason(plain) == .timeUp)
        #expect(AwakeEndReason.focusDone.notifies)
    }

    @Test func minutesLeftRoundsUp() {
        let s = AwakeSession(started: now, end: .at(now.addingTimeInterval(24 * 60 + 5)), focus: true)
        #expect(s.minutesLeft(now: now) == 25)
        #expect(s.minutesLeft(now: now.addingTimeInterval(25 * 60)) == 0)
        #expect(AwakeSession(started: now, end: .never).minutesLeft(now: now) == nil)
        #expect(FocusPreset.minutes == [25, 50, 90])
    }
}
