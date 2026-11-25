import Foundation
import Testing
@testable import VibeCheck

struct ItemOptionsTests {
    private let now = Date()
    private func window(_ used: Double, _ minutes: Int) -> RateWindow {
        RateWindow(usedPercent: used, windowMinutes: minutes, resetsAt: now.addingTimeInterval(3600))
    }
    private func tokens(_ n: Int) -> TokenCounts { TokenCounts(input: n) }

    private var sample: AgentUsageSample {
        var s = AgentUsageSample(scanned: true)
        let block = UsageBlock(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(3600), tokens: tokens(40))
        s.agents = [
            AgentSummary(agent: .claude, today: tokens(100), week: tokens(700), block: block),
            AgentSummary(agent: .codex, today: tokens(10), week: tokens(30), limits: [window(30, 10080), window(5, 300)]),
            AgentSummary(agent: .copilot, today: tokens(1), week: tokens(2)),
        ]
        return s
    }

    @Test func tokensCountTheChosenAgents() {
        var o = ItemOptions()
        #expect(sample.menuBarContent(o) == .tokens(111))           // all agents, today
        o.agents = [.claude]
        #expect(sample.menuBarContent(o) == .tokens(100))
        o.agentValue = .tokensWeek
        #expect(sample.menuBarContent(o) == .tokens(700))
        o.agentValue = .tokensWindow
        #expect(sample.menuBarContent(o) == .tokens(40))
        o.agents = [.codex, .copilot]
        #expect(sample.menuBarContent(o) == .tokens(0))             // neither has a 5-hour window
    }

    @Test func limitsPickWindowsAndLeftOrUsed() {
        var o = ItemOptions()
        o.agentValue = .limitsLeft
        o.agents = [.codex]
        #expect(sample.menuBarContent(o) == .limits([window(5, 300), window(30, 10080)], used: false))
        o.agentWindows = .session
        #expect(sample.menuBarContent(o) == .limits([window(5, 300)], used: false))
        o.agentWindows = .longest
        o.agentValue = .limitsUsed
        #expect(sample.menuBarContent(o) == .limits([window(30, 10080)], used: true))
    }

    @Test func claudeWithoutLiveLimitsUsesItsEstimate() {
        var o = ItemOptions()
        o.agentValue = .limitsLeft
        o.agents = [.claude]
        guard case .windowEstimate(let agent, let block, let today) = sample.menuBarContent(o) else { Issue.record("no estimate"); return }
        #expect(agent == .claude && block.tokens.total == 40 && today == 100)
        // All agents: Codex has real limits, so they're shown rather than Claude's estimate.
        o.agents = []
        #expect(sample.menuBarContent(o) == .limits([window(5, 300), window(30, 10080)], used: false))
        // No agent with limits and no 5-hour estimate: falls back to tokens.
        o.agents = [.copilot]
        #expect(sample.menuBarContent(o) == .tokens(1))
    }

    @Test func antigravityWithoutLiveLimitsUsesItsEstimate() {
        let block = UsageBlock(start: now.addingTimeInterval(-1800), end: now.addingTimeInterval(16200), tokens: tokens(25))
        var s = AgentUsageSample(scanned: true)
        s.agents = [AgentSummary(agent: .antigravity, today: tokens(60), week: tokens(200), block: block)]
        var o = ItemOptions()
        o.agentValue = .limitsLeft
        o.agents = [.antigravity]
        guard case .windowEstimate(let agent, let estimated, let today) = s.menuBarContent(o) else { Issue.record("no estimate"); return }
        #expect(agent == .antigravity && estimated.tokens.total == 25 && today == 60)
        #expect(s.menuBarAgent(o) == .antigravity)
        o.agentValue = .tokensWindow
        #expect(s.menuBarContent(o) == .tokens(25))
    }

    @Test func decodesPartialAndUnknownValues() throws {
        let partial = #"{"agentValue":"limitsUsed","agents":["claude"],"memoryValue":"nonsense"}"#
        let o = try JSONDecoder().decode(ItemOptions.self, from: Data(partial.utf8))
        #expect(o.agentValue == .limitsUsed)
        #expect(o.agents == [.claude])
        #expect(o.memoryValue == .percent)     // unknown value → default
        #expect(o.agentShowReset)              // missing → default
        let roundTrip = try JSONDecoder().decode(ItemOptions.self, from: JSONEncoder().encode(o))
        #expect(roundTrip == o)
    }

    @Test func compactFormats() {
        #expect(Fmt.compactBytes(512 * 1_048_576) == "512M")
        #expect(Fmt.compactBytes(12.34 * 1_073_741_824) == "12.3G")
        #expect(Fmt.compactBytes(250 * 1_073_741_824) == "250G")
        #expect(Fmt.compactBytes(1.5 * 1024 * 1_073_741_824) == "1.5T")
        #expect(Fmt.clockDuration(205) == "3:25")
        #expect(Fmt.clockDuration(7) == "0:07")
    }
}
