import Foundation
import Testing
@testable import VibeCheck

struct LimitPaceTests {
    // 5-hour window resetting at 12:00, so it started at 07:00.
    private let resets = Date(timeIntervalSince1970: 1_800_000_000)
    private func window(used: Double, minutes: Int = 300) -> RateWindow {
        RateWindow(usedPercent: used, windowMinutes: minutes, resetsAt: resets)
    }
    private func at(hoursBeforeReset h: Double) -> Date { resets.addingTimeInterval(-h * 3600) }

    @Test func elapsedLeftAndBurn() {
        let w = window(used: 51)
        let now = at(hoursBeforeReset: 2.7)          // 2.3 h in
        #expect(abs(w.elapsedFraction(now: now) - 0.46) < 0.001)
        #expect(w.leftPercent == 49)
        #expect(abs(w.burnPerHour(now: now)! - 51 / 2.3) < 0.001)
        #expect(w.burnPerHour(now: at(hoursBeforeReset: 4.95)) == nil)   // 3 minutes in
        #expect(w.burnPerHour(now: resets.addingTimeInterval(60)) == nil) // over
        #expect(window(used: 120).leftPercent == 0)
    }

    @Test func paceWarnsOnlyWhenClearlyAhead() {
        let now = at(hoursBeforeReset: 2.5)          // halfway
        #expect(!window(used: 50).isAheadOfPace(now: now))
        #expect(!window(used: 54).isAheadOfPace(now: now))
        #expect(window(used: 60).isAheadOfPace(now: now))
    }

    @Test func countdownAndTitles() {
        let w = window(used: 0, minutes: 10080)
        #expect(w.countdown(now: at(hoursBeforeReset: 142)) == "5d 22h")
        #expect(w.countdown(now: at(hoursBeforeReset: 2.7)) == "2h 42m")
        #expect(w.countdown(now: at(hoursBeforeReset: 0.3)) == "18m")
        #expect(w.countdown(now: resets.addingTimeInterval(5)) == "now")
        #expect(window(used: 0).cardTitle == "Current session")
        #expect(w.cardTitle == "Weekly limit")
    }

    @Test func runsOutForecast() {
        // 2.5 h in, 60% used: 24%/h, 40% left -> 1h40m, and the window has 2.5 h left.
        let now = at(hoursBeforeReset: 2.5)
        let ahead = window(used: 60).runsOutAt(now: now)
        #expect(ahead != nil)
        #expect(abs(ahead!.timeIntervalSince(now) - 40.0 / 24 * 3600) < 1)
        // Behind pace: lasts until reset.
        #expect(window(used: 30).runsOutAt(now: now) == nil)
        // Too early: no burn rate yet.
        #expect(window(used: 20).runsOutAt(now: at(hoursBeforeReset: 4.95)) == nil)
        // Past the reset.
        #expect(window(used: 90).runsOutAt(now: resets.addingTimeInterval(60)) == nil)
        // Nothing used, or everything used.
        #expect(window(used: 0).runsOutAt(now: now) == nil)
        #expect(window(used: 100).runsOutAt(now: now) == nil)
    }
}
