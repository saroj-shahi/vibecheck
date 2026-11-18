import Foundation
import Testing
@testable import VibeCheck

struct AgentUsageTests {
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func claudeLine(id: String, request: String = "req_1", time: String, model: String = "claude-opus-5-5",
                    input: Int = 10, output: Int = 100, cacheWrite: Int = 1000, cacheRead: Int = 5000, cwd: String = "/x/VibeCheck") -> String {
        #"{"type":"assistant","timestamp":"\#(time)","requestId":"\#(request)","cwd":"\#(cwd)","message":{"id":"\#(id)","model":"\#(model)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":\#(cacheWrite),"cache_read_input_tokens":\#(cacheRead)}}}"#
    }

    func codexCount(time: String, input: Int, cached: Int, output: Int, used: Double = 12) -> String {
        #"{"timestamp":"\#(time)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"cache_write_input_tokens":0,"output_tokens":\#(output)}},"rate_limits":{"primary":{"used_percent":\#(used),"window_minutes":300,"resets_at":1900000000},"secondary":{"used_percent":40,"window_minutes":10080,"resets_at":1900500000}}}}"#
    }

    @Test func parsesClaudeUsageAndSkipsOtherLines() throws {
        let parsed = try #require(AgentLogParser.claude(Data(claudeLine(id: "msg_1", time: "2026-11-18T07:05:35.220Z").utf8)))
        #expect(parsed.key == "msg_1:req_1")
        #expect(parsed.entry.tokens == TokenCounts(input: 10, output: 100, cacheWrite: 1000, cacheRead: 5000))
        #expect(parsed.entry.project == "VibeCheck")
        #expect(AgentLogParser.claude(Data(#"{"type":"user","message":{"usage":{}}}"#.utf8)) == nil)
        #expect(AgentLogParser.claude(Data(claudeLine(id: "m", time: "2026-11-18T07:05:35Z", model: "<synthetic>").utf8)) == nil)
    }

    @Test func codexUsesDeltasOfRunningTotalsAndReadsLimits() {
        var state = AgentLogParser.CodexState()
        _ = AgentLogParser.codex(Data(#"{"type":"turn_context","payload":{"model":"gpt-6-luna","cwd":"/a/bin"}}"#.utf8), state: &state)
        let first = AgentLogParser.codex(Data(codexCount(time: "2026-11-17T05:30:48.511Z", input: 1000, cached: 400, output: 50).utf8), state: &state)
        #expect(first.entry?.tokens == TokenCounts(input: 600, output: 50, cacheWrite: 0, cacheRead: 400))
        #expect(first.entry?.model == "gpt-6-luna")
        #expect(first.entry?.project == "bin")
        #expect(first.limits?.map(\.title) == ["5-hour limit", "Weekly limit"])
        let same = AgentLogParser.codex(Data(codexCount(time: "2026-11-17T05:31:00Z", input: 1000, cached: 400, output: 50).utf8), state: &state)
        #expect(same.entry == nil) // repeated totals add nothing
        let next = AgentLogParser.codex(Data(codexCount(time: "2026-11-17T05:32:00Z", input: 1500, cached: 800, output: 80).utf8), state: &state)
        #expect(next.entry?.tokens == TokenCounts(input: 100, output: 30, cacheWrite: 0, cacheRead: 400))
    }

    @Test func fiveHourBlockStartsOnTheHourAndEnds() {
        func entry(_ hour: Double, _ total: Int) -> UsageEntry {
            UsageEntry(time: Date(timeIntervalSince1970: 1_800_000_000 + hour * 3600), agent: .claude, model: "m",
                       project: "p", tokens: TokenCounts(input: total))
        }
        let base = Date(timeIntervalSince1970: 1_800_000_000) // 08:00 UTC
        let entries = [entry(0.5, 1), entry(2, 2), entry(5.6, 4), entry(6, 8)]
        let block = AgentLogParser.currentBlock(entries, now: base.addingTimeInterval(7 * 3600), calendar: utc)
        #expect(block?.start == base.addingTimeInterval(5 * 3600)) // second block starts at 13:00
        #expect(block?.tokens.total == 12)
        #expect(AgentLogParser.currentBlock(entries, now: base.addingTimeInterval(11 * 3600), calendar: utc) == nil)
    }

    @Test func tokenFormatting() {
        #expect(Fmt.tokens(840) == "840")
        #expect(Fmt.tokens(12_400) == "12K")
        #expect(Fmt.tokens(1_240_000) == "1.2M")
        #expect(Fmt.tokens(412_000_000) == "412M")
        #expect(Fmt.tokens(1_300_000_000) == "1.3B")
    }

    @Test func shortcutKeysRunOneToNineThenZero() {
        #expect(Module.cpu.shortcutKey == "1")
        #expect(Module.weather.shortcutKey == "9")
        #expect(Module.agents.shortcutKey == "0")
        #expect(Module.forShortcutKey("0") == .agents)
    }

    /// Reads real files from a temp folder: dedupes repeats, picks up appended lines, ignores a half-written line.
    @Test func scannerReadsIncrementally() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "vibecheck-agents-\(UUID().uuidString)")
        let claude = root.appending(path: "claude/proj"), codex = root.appending(path: "codex/2026")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))
        let file = claude.appending(path: "s.jsonl")
        let line = claudeLine(id: "a", time: stamp, input: 1, output: 1, cacheWrite: 1, cacheRead: 1)
        try (line + "\n" + line + "\n").write(to: file, atomically: true, encoding: .utf8)

        let scanner = AgentUsageScanner(claudeRoots: [root.appending(path: "claude")], codexRoots: [root.appending(path: "codex")])
        let first = scanner.scan(now: now)
        #expect(first.today.total == 4)
        #expect(first.agents.map(\.agent) == [.claude, .codex])

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((claudeLine(id: "b", time: stamp, input: 10, output: 0, cacheWrite: 0, cacheRead: 0) + "\n{\"partial").utf8))
        try handle.close()
        #expect(scanner.scan(now: now).today.total == 14)
    }
}
