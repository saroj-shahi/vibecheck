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

    @Test func menuBarShowsClaudeFirstEvenWithoutLiveLimits() {
        let codexLimits = [window(used: 10, minutes: 10080), window(used: 5)]
        var sample = AgentUsageSample()
        sample.agents = [AgentSummary(agent: .codex, limits: codexLimits)]
        // No Claude Code on this Mac: the other agent's limits, shortest first.
        #expect(sample.menuBarLimits == .limits(.codex, codexLimits.reversed()))

        // Claude Code in use, live limits off: its local estimate, not Codex's limits.
        let block = UsageBlock(start: resets.addingTimeInterval(-3600), end: resets, tokens: TokenCounts(input: 5))
        sample.agents.insert(AgentSummary(agent: .claude, block: block), at: 0)
        #expect(sample.menuBarLimits == .claudeEstimate(block))

        // Live Claude limits win.
        sample.agents[0].limits = [window(used: 30)]
        #expect(sample.menuBarLimits == .limits(.claude, [window(used: 30)]))

        // Claude Code with no current window and no limits: fall back to another agent's limits.
        sample.agents[0] = AgentSummary(agent: .claude)
        #expect(sample.menuBarLimits == .limits(.codex, codexLimits.reversed()))
        sample.agents = [AgentSummary(agent: .claude)]
        #expect(sample.menuBarLimits == nil)
    }
}
