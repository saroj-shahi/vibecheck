import Foundation
import Testing
@testable import VibeCheck

struct AntigravityLimitsTests {
    let full = #"""
    {"conversation_id":"","status":"SUCCESS","response":"Gemini Models\tWeekly Limit Remaining\t52%\t2026-12-01T04:04:27Z\n","duration_seconds":0,"num_turns":0,"usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0},"command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"gemini-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":0.52,"reset_time":"2026-12-01T04:04:27Z"},{"id":"gemini-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":0.73,"reset_time":"2026-11-25T12:38:44Z"}]},{"name":"Claude and GPT models","buckets":[{"id":"3p-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":1,"reset_time":"2026-12-02T08:52:35Z"},{"id":"3p-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":0.85,"reset_time":"2026-11-25T13:52:35Z"}]}]}}}
    """#

    @Test func parsesMultiGroupResponse() {
        let usage = AntigravityLimitsClient.parse(Data(full.utf8))
        #expect(usage.available)
        #expect(usage.windows.count == 4)
        #expect(usage.windows.map(\.windowMinutes) == [300, 10080, 300, 10080])
        #expect(usage.windows.map(\.title) == ["5-hour · Gemini", "Weekly · Gemini", "5-hour · Claude & GPT", "Weekly · Claude & GPT"])
        #expect(usage.windows.map(\.cardTitle) == ["5-hour · Gemini", "Weekly · Gemini", "5-hour · Claude & GPT", "Weekly · Claude & GPT"])
        #expect(abs(usage.windows[0].usedPercent - 27) < 0.001)
        #expect(abs(usage.windows[1].usedPercent - 48) < 0.001)
        #expect(abs(usage.windows[2].usedPercent - 15) < 0.001)
        #expect(abs(usage.windows[3].usedPercent - 0) < 0.001)
    }

    @Test func singleGroupUsesDefaultWindowTitles() {
        let json = #"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"gemini-5h","window":"5h","remaining_fraction":0.6,"reset_time":"2026-11-25T12:38:44Z"},{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.4,"reset_time":"2026-12-01T04:04:27Z"}]}]}}}"#
        let usage = AntigravityLimitsClient.parse(Data(json.utf8))
        #expect(usage.available)
        #expect(usage.windows.map(\.name) == [nil, nil])
        #expect(usage.windows.map(\.cardTitle) == ["Current session", "Weekly limit"])
        #expect(abs(usage.windows[0].usedPercent - 40) < 0.001)
        #expect(abs(usage.windows[1].usedPercent - 60) < 0.001)
    }

    @Test func dropsMalformedBucketsAndHandlesBadPayloads() {
        let partial = #"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"window":"5h","remaining_fraction":null,"reset_time":"2026-11-25T12:38:44Z"},{"window":"weekly","remaining_fraction":0.5,"reset_time":null},{"window":"unknown","remaining_fraction":0.5,"reset_time":"2026-12-01T04:04:27Z"}]}]}}}"#
        let parsed = AntigravityLimitsClient.parse(Data(partial.utf8))
        #expect(parsed.available && parsed.windows.isEmpty)

        #expect(!AntigravityLimitsClient.parse(Data(#"{"status":"ERROR","command":{"name":"usage"}}"#.utf8)).available)
        #expect(!AntigravityLimitsClient.parse(Data("not json".utf8)).available)
        #expect(!AntigravityLimitsClient.parse(Data()).available)
    }

    @Test func classifiesSignedOutAndErrors() {
        #expect(AntigravityLimitsClient.classify(stdout: Data(), stderr: Data("Error: user is not logged in".utf8), exitCode: 1) == .signedOut)
        #expect(AntigravityLimitsClient.classify(stdout: Data(#"{"status":"ERROR","response":"Please sign in to continue"}"#.utf8), stderr: Data(), exitCode: 1) == .signedOut)
        #expect(AntigravityLimitsClient.classify(stdout: Data("timeout".utf8), stderr: Data(), exitCode: 1) == .noAnswer)
        if case .usage(let windows) = AntigravityLimitsClient.classify(stdout: Data(full.utf8), stderr: Data(), exitCode: 0) {
            #expect(windows.count == 4)
        } else {
            Issue.record("expected usage windows")
        }
    }

    @Test func liveLimitsReplaceAntigravityOnlyWhenFresh() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let local = RateWindow(usedPercent: 1, windowMinutes: 300, resetsAt: now.addingTimeInterval(1000))
        let live = [
            RateWindow(usedPercent: 27, windowMinutes: 300, resetsAt: now.addingTimeInterval(3600), name: "5-hour · Gemini"),
            RateWindow(usedPercent: 48, windowMinutes: 10080, resetsAt: now.addingTimeInterval(86400), name: "Weekly · Gemini"),
        ]
        var sample = AgentUsageSample(scanned: true)
        sample.agents = [AgentSummary(agent: .claude, limits: [local]), AgentSummary(agent: .antigravity)]

        let fresh = AntigravityLiveLimits.merge(sample, live: live, fetchedAt: now.addingTimeInterval(-60), now: now)
        #expect(fresh.agents[0].limits == [local])
        #expect(fresh.agents[1].limits == live)

        let expired = AntigravityLiveLimits.merge(sample,
                                                  live: [live[1], RateWindow(usedPercent: 90, windowMinutes: 300, resetsAt: now)],
                                                  fetchedAt: now.addingTimeInterval(-60), now: now)
        #expect(expired.agents[1].limits == [live[1]])

        #expect(AntigravityLiveLimits.merge(sample, live: live, fetchedAt: now.addingTimeInterval(-16 * 60), now: now) == sample)
        #expect(AntigravityLiveLimits.merge(sample, live: [], fetchedAt: now, now: now) == sample)
        #expect(AntigravityLiveLimits.merge(sample, live: live, fetchedAt: nil, now: now) == sample)
    }

    @Test func menuBarPicksPrimarySessionAndWeeklyForMultiGroupLimits() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let usage = AntigravityLimitsClient.parse(Data(full.utf8))
        let shifted = usage.windows.map { RateWindow(usedPercent: $0.usedPercent, windowMinutes: $0.windowMinutes, resetsAt: now.addingTimeInterval(3600), name: $0.name) }
        var sample = AgentUsageSample(scanned: true)
        sample.agents = [AgentSummary(agent: .antigravity, limits: shifted)]

        var o = ItemOptions()
        o.agentValue = .limitsLeft
        o.agentWindows = .both
        #expect(sample.menuBarContent(o) == .limits([shifted[0], shifted[1]], used: false))
        o.agentWindows = .session
        #expect(sample.menuBarContent(o) == .limits([shifted[0]], used: false))
        o.agentWindows = .longest
        #expect(sample.menuBarContent(o) == .limits([shifted[1]], used: false))
    }

    @Test func findsCLIInHomeLocalBin() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vc-agy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let bin = dir.appending(path: ".local/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let agy = bin.appending(path: "agy")
        try "#!/bin/sh\nexit 0\n".write(to: agy, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: agy.path)

        #expect(AntigravityLimitsClient.findCLI(home: dir.path)?.path == agy.path)
    }
}
