import Foundation
import SQLite3
import Testing
@testable import VibeCheck

struct MoreAgentsTests {
    private let start = #"{"type":"session.start","id":"s1","timestamp":"2026-11-18T07:00:00.000Z","data":{"context":{"cwd":"/Users/me/code/VibeCheck"}}}"#
    private let usage = #"{"type":"session.usage_record","id":"u1","timestamp":"2026-11-18T07:02:54.671Z","data":{"usage":{"model":"gpt-x","inputTokens":20389,"outputTokens":441,"cacheReadTokens":2304,"cacheWriteTokens":10,"reasoningTokens":320}}}"#
    private let quota = #"{"type":"model.model_call_success","id":"m1","timestamp":"2026-11-18T07:03:29.533Z","data":{"quotaSnapshots":{"chat":{"isUnlimitedEntitlement":false,"entitlementRequests":200,"remainingPercentage":97.1,"resetDate":"2026-12-01T00:00:00Z"},"completions":{"isUnlimitedEntitlement":true,"entitlementRequests":2000,"remainingPercentage":98,"resetDate":"2026-12-01T00:00:00Z"},"premium_interactions":{"isUnlimitedEntitlement":false,"entitlementRequests":0,"remainingPercentage":0,"resetDate":"2026-12-01T00:00:00Z"}}}}"#

    @Test func copilotUsageAndQuota() throws {
        var state = AgentLogParser.CopilotState()
        _ = AgentLogParser.copilot(Data(start.utf8), state: &state)
        #expect(state.project == "VibeCheck")
        let u = AgentLogParser.copilot(Data(usage.utf8), state: &state)
        let entry = try #require(u.entry)
        #expect(u.key == "u1")
        #expect(entry.agent == .copilot && entry.model == "gpt-x" && entry.project == "VibeCheck")
        // Input includes cache reads (OpenAI style); output already includes reasoning.
        #expect(entry.tokens == TokenCounts(input: 18085, output: 441, cacheWrite: 10, cacheRead: 2304))

        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let q = AgentLogParser.copilot(Data(quota.utf8), state: &state, calendar: utc)
        let limits = try #require(q.limits)
        #expect(limits.count == 1)                       // unlimited and zero-entitlement quotas are skipped
        #expect(limits[0].title == "Chat requests")
        #expect(abs(limits[0].usedPercent - 2.9) < 0.001)
        #expect(limits[0].windowMinutes == 30 * 1440)    // November
    }

    @Test func openCodeMessage() throws {
        let row = #"{"role":"assistant","modelID":"m1","path":{"cwd":"/tmp/proj"},"time":{"created":1795000000000},"tokens":{"input":100,"output":20,"reasoning":5,"cache":{"read":7,"write":3}}}"#
        let entry = try #require(AgentLogParser.opencode(Data(row.utf8)))
        #expect(entry.tokens == TokenCounts(input: 100, output: 25, cacheWrite: 3, cacheRead: 7))
        #expect(entry.project == "proj" && entry.model == "m1" && entry.agent == .opencode)
        #expect(entry.time == Date(timeIntervalSince1970: 1_795_000_000))
        #expect(AgentLogParser.opencode(Data(#"{"role":"user","tokens":{"input":5}}"#.utf8)) == nil)
        #expect(AgentLogParser.opencode(Data(#"{"role":"assistant","time":{"created":1},"tokens":{"input":0,"output":0}}"#.utf8)) == nil)
    }

    @Test func scannerReadsCopilotFilesAndOpenCodeDatabase() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vc-agents-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        let iso = ISO8601DateFormatter()
        let session = dir.appending(path: "copilot/s1")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let fresh = usage.replacingOccurrences(of: "2026-11-18T07:02:54.671Z", with: iso.string(from: now.addingTimeInterval(-60)))
        // The same record twice: counted once.
        try (start + "\n" + fresh + "\n" + fresh + "\n").write(to: session.appending(path: "events.jsonl"), atomically: true, encoding: .utf8)

        let dbURL = dir.appending(path: "opencode.db")
        var db: OpaquePointer?
        #expect(sqlite3_open(dbURL.path, &db) == SQLITE_OK)
        let created = Int64(now.addingTimeInterval(-120).timeIntervalSince1970 * 1000)
        let json = #"{"role":"assistant","modelID":"m1","time":{"created":\#(created)},"tokens":{"input":100,"output":20,"reasoning":0,"cache":{"read":0,"write":0}}}"#
        let sql = "CREATE TABLE message (id text PRIMARY KEY, session_id text, time_created integer, time_updated integer, data text);"
            + "INSERT INTO message VALUES ('msg1','s',\(created),\(created),'\(json)');"
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        let scanner = AgentUsageScanner(claudeRoots: [dir.appending(path: "none")], codexRoots: [dir.appending(path: "none")],
                                        copilotRoots: [dir.appending(path: "copilot")], antigravityRoots: [], opencodeDB: dbURL,
                                        claudeConfig: URL(fileURLWithPath: "/nonexistent/.claude.json"))
        let sample = scanner.scan(now: now, fullWalk: true)
        #expect(Set(sample.agents.map(\.agent)) == [.copilot, .opencode])
        #expect(sample.agents.first { $0.agent == .copilot }?.today.total == 18085 + 441 + 10 + 2304)
        #expect(sample.agents.first { $0.agent == .opencode }?.today.total == 120)
        // A rescan with nothing changed keeps the same totals (no double counting).
        #expect(scanner.scan(now: now).today == sample.today)
    }

    @Test func antigravityTranscriptParsingAndScanning() throws {
        let modelLine = #"{"step_index":4,"type":"PLANNER_RESPONSE","source":"MODEL","status":"DONE","created_at":"2026-11-24T04:04:34Z","model":"gemini-4-neon-high","input_tokens":3988,"output_tokens":347,"cache_read_tokens":14526}"#
        let parsed = try #require(AgentLogParser.antigravity(Data(modelLine.utf8)))
        #expect(parsed.key == "step:4")
        #expect(parsed.entry.agent == .antigravity)
        #expect(parsed.entry.model == "gemini-4-neon-high")
        #expect(parsed.entry.tokens == TokenCounts(input: 3988, output: 347, cacheWrite: 0, cacheRead: 14526))
        #expect(AgentLogParser.antigravity(Data(#"{"step_index":0,"type":"USER_INPUT","source":"USER_EXPLICIT","created_at":"2026-11-24T04:04:00Z"}"#.utf8)) == nil)
        #expect(AgentLogParser.antigravity(Data(#"{"step_index":2,"type":"PLANNER_RESPONSE","source":"MODEL","created_at":"2026-11-24T04:04:10Z","input_tokens":0,"output_tokens":0}"#.utf8)) == nil)

        let dir = FileManager.default.temporaryDirectory.appending(path: "vc-antigravity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let logs = dir.appending(path: "brain/conv-1/.system_generated/logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-30))
        let fresh = modelLine.replacingOccurrences(of: "2026-11-24T04:04:34Z", with: stamp)
        // Write transcript.jsonl (with a duplicate step_index) AND transcript_full.jsonl (must be ignored).
        try (fresh + "\n" + fresh + "\n").write(to: logs.appending(path: "transcript.jsonl"), atomically: true, encoding: .utf8)
        try (fresh + "\n").write(to: logs.appending(path: "transcript_full.jsonl"), atomically: true, encoding: .utf8)

        let scanner = AgentUsageScanner(claudeRoots: [], codexRoots: [], copilotRoots: [],
                                        antigravityRoots: [dir.appending(path: "brain")],
                                        opencodeDB: dir.appending(path: "none.db"),
                                        claudeConfig: URL(fileURLWithPath: "/nonexistent/.claude.json"))
        let sample = scanner.scan(now: now, fullWalk: true)
        #expect(sample.agents.map(\.agent) == [.antigravity])
        #expect(sample.agents.first?.today.total == 3988 + 347 + 14526)
        #expect(sample.agents.first?.block?.tokens.total == 3988 + 347 + 14526)
        #expect(sample.activeSessions.count == 1 && sample.activeSessions.first?.agent == .antigravity)
        #expect(scanner.scan(now: now).today == sample.today)
    }
}
