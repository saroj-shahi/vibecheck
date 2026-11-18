import Foundation
import Testing
@testable import VibeCheck

struct AgentExtrasTests {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func entry(_ time: Date, _ tokens: Int, _ agent: AgentKind = .claude) -> UsageEntry {
        UsageEntry(time: time, agent: agent, model: "m", project: "p", tokens: TokenCounts(input: tokens))
    }

    @Test func dailyTotalsAndLastHour() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)          // 2027-01-15 08:00 UTC
        let entries = [
            entry(now.addingTimeInterval(-30 * 60), 100),             // today, last hour
            entry(now.addingTimeInterval(-2 * 3600), 50),             // today
            entry(now.addingTimeInterval(-86400), 7),                 // yesterday
            entry(now.addingTimeInterval(-6 * 86400), 3),             // 6 days ago (first bar)
            entry(now.addingTimeInterval(-8 * 86400), 999),           // too old
        ]
        let sample = AgentLogParser.summarize(entries, limits: [:], present: [.claude], now: now, calendar: calendar)
        #expect(sample.daily == [3, 0, 0, 0, 0, 7, 150])
        #expect(sample.lastHour == 100)
        #expect(AlertEngine.agentTokensPerHour(sample, enabled: true) == 0.0001)
        #expect(AlertEngine.agentTokensPerHour(sample, enabled: false) == nil)
        #expect(AlertEngine.agentTokensPerHour(AgentUsageSample(), enabled: true) == nil)
    }

    @Test func workingNowMeansActiveInTheLastTwoMinutes() {
        let now = Date()
        #expect(AgentSummary(agent: .codex, lastActive: now.addingTimeInterval(-60)).isWorking(now: now))
        #expect(!AgentSummary(agent: .codex, lastActive: now.addingTimeInterval(-300)).isWorking(now: now))
        #expect(!AgentSummary(agent: .codex).isWorking(now: now))
    }

    @Test func agentTokensAlertMetric() {
        #expect(AlertMetric.agentTokens.unit == "M")
        #expect(AlertMetric.agentTokens.range == 1...500)
        let rule = AlertRule(metric: .agentTokens, comparison: .above, threshold: 50, duration: 300)
        #expect(rule.describe(current: 62.4) == "Agent tokens per hour has been above 50M for 5 min. Now 62M.")
    }

    /// Copilot's quota is read from the newest session even when it's older than a week; its usage isn't counted.
    @Test func copilotQuotaFromAnOldSession() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vc-copilot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = dir.appending(path: "s1")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let now = Date()
        let iso = ISO8601DateFormatter()
        let old = iso.string(from: now.addingTimeInterval(-10 * 86400))
        let reset = iso.string(from: now.addingTimeInterval(5 * 86400))
        let lines = [
            #"{"type":"session.usage_record","id":"u1","timestamp":"\#(old)","data":{"usage":{"model":"m","inputTokens":10,"outputTokens":5}}}"#,
            #"{"type":"model.model_call_success","id":"m1","timestamp":"\#(old)","data":{"quotaSnapshots":{"chat":{"isUnlimitedEntitlement":false,"entitlementRequests":200,"remainingPercentage":80,"resetDate":"\#(reset)"}}}}"#,
        ]
        let file = session.appending(path: "events.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10 * 86400)], ofItemAtPath: file.path)

        let scanner = AgentUsageScanner(claudeRoots: [], codexRoots: [], copilotRoots: [dir], opencodeDB: dir.appending(path: "none.db"))
        let copilot = try #require(scanner.scan(now: now, fullWalk: true).agents.first { $0.agent == .copilot })
        #expect(copilot.week.total == 0)
        #expect(copilot.limits.map(\.title) == ["Chat requests"])
        #expect(copilot.limits.first?.usedPercent == 20)
    }
}
