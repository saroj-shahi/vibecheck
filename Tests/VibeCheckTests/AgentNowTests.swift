import Foundation
import Testing
@testable import VibeCheck

struct AgentNowTests {
    @Test func modelAndPlanNames() {
        #expect(AgentNames.model("claude-opus-5-5") == "Opus 5.5")
        #expect(AgentNames.model("claude-sonnet-4-5-20250929") == "Sonnet 4.5")
        #expect(AgentNames.model("claude-haiku-5-5") == "Haiku 5.5")
        #expect(AgentNames.model("gpt-5.4-codex") == "gpt-5.4-codex")
        #expect(AgentNames.plan("claude_team") == "Team")
        #expect(AgentNames.plan("free") == "Free")
        #expect(AgentNames.plan("claude_max_20x") == nil || AgentNames.plan("max_20x") == "Max")
        #expect(AgentNames.plan("") == nil && AgentNames.plan(nil) == nil)
    }

    @Test func claudeAccountReadsOnlyNameAndPlan() {
        let json = #"{"projects":{"x":{}},"oauthAccount":{"displayName":"Saroj","emailAddress":"a@b.c","organizationType":"claude_team"}}"#
        #expect(AgentNames.claudeAccount(Data(json.utf8)) == AgentAccount(name: "Saroj", plan: "Team"))
        #expect(AgentNames.claudeAccount(Data("{}".utf8)) == nil)
        #expect(AgentNames.claudeAccount(Data(#"{"oauthAccount":{"fullName":"S S"}}"#.utf8)) == AgentAccount(name: "S S", plan: nil))
    }

    @Test func activeSessionsAreRecentAndTotalled() {
        let now = Date()
        func e(_ ago: TimeInterval, _ session: String, out: Int, model: String = "claude-opus-5-5") -> UsageEntry {
            UsageEntry(time: now.addingTimeInterval(-ago), agent: .claude, model: model, project: "VibeCheck",
                       tokens: TokenCounts(output: out), session: session)
        }
        let active = AgentLogParser.activeSessions([
            e(240, "a", out: 10), e(30, "a", out: 5, model: "claude-sonnet-5-5"),   // running: 4 min, 15 written
            e(600, "b", out: 99),                                                  // idle for 10 min
            e(10, "", out: 7),                                                     // no session: ignored
        ], now: now)
        #expect(active.count == 1)
        #expect(active[0].session == "a" && active[0].tokens.output == 15 && active[0].model == "claude-sonnet-5-5")
        #expect(abs(active[0].started.timeIntervalSince(now.addingTimeInterval(-240))) < 0.001)
    }

    @Test func scannerAddsAccountsSessionsAndCodexPlan() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vc-now-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        let iso = ISO8601DateFormatter()
        let claudeDir = dir.appending(path: "claude/proj")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let line = #"{"type":"assistant","timestamp":"\#(iso.string(from: now.addingTimeInterval(-20)))","cwd":"/x/VibeCheck","requestId":"r1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":3,"output_tokens":21000}}}"#
        try (line + "\n").write(to: claudeDir.appending(path: "s1.jsonl"), atomically: true, encoding: .utf8)
        let codexDir = dir.appending(path: "codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let rate = #"{"timestamp":"\#(iso.string(from: now.addingTimeInterval(-60)))","type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"free","primary":{"used_percent":1.0,"window_minutes":43200,"resets_at":\#(Int(now.timeIntervalSince1970) + 86400)}}}}"#
        try (rate + "\n").write(to: codexDir.appending(path: "r.jsonl"), atomically: true, encoding: .utf8)
        let config = dir.appending(path: ".claude.json")
        try #"{"oauthAccount":{"displayName":"Saroj","organizationType":"claude_team"}}"#.write(to: config, atomically: true, encoding: .utf8)

        let scanner = AgentUsageScanner(claudeRoots: [dir.appending(path: "claude")], codexRoots: [codexDir], copilotRoots: [],
                                        opencodeDB: dir.appending(path: "none.db"), claudeConfig: config)
        let sample = scanner.scan(now: now, fullWalk: true)
        #expect(sample.agents.first { $0.agent == .claude }?.account == AgentAccount(name: "Saroj", plan: "Team"))
        #expect(sample.agents.first { $0.agent == .codex }?.account.plan == "Free")
        #expect(sample.activeSessions.map(\.project) == ["VibeCheck"])
        #expect(sample.activeSessions.first?.tokens.output == 21000)
    }

    @Test func limitKeysAreUniqueAndLongWindowsBurnPerDay() {
        let reset = Date().addingTimeInterval(12 * 86400)
        let chat = RateWindow(usedPercent: 9, windowMinutes: 43200, resetsAt: reset, name: "Chat requests")
        let completions = RateWindow(usedPercent: 2.5, windowMinutes: 43200, resetsAt: reset, name: "Completions")
        #expect(chat.key != completions.key)
        // 9% over 18 days = 0.5% a day.
        #expect(chat.burnText(now: Date()) == "0.5%/day")
        let session = RateWindow(usedPercent: 50, windowMinutes: 300, resetsAt: Date().addingTimeInterval(2.5 * 3600))
        #expect(session.burnText(now: Date()) == "20.0%/hr")
    }
}
