import Foundation
import Testing
@testable import VibeCheck

struct ClaudeLimitsTests {
    let full = #"{"subscription_type":"team","rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":86,"resets_at":"2026-11-18T11:50:00.420974+00:00"},"seven_day":{"utilization":38,"resets_at":"2026-11-24T08:00:00.420993+00:00"},"seven_day_opus":null,"seven_day_sonnet":null,"extra":null}}"#

    @Test func parsesFullResponse() {
        let usage = ClaudeLimitsClient.parse(Data(full.utf8))
        #expect(usage.available && usage.plan == "team")
        #expect(usage.windows.map(\.windowMinutes) == [300, 10080])
        #expect(usage.windows.map(\.usedPercent) == [86, 38])
        #expect(usage.windows.allSatisfy { $0.name == nil })
        #expect(abs(usage.windows[0].resetsAt.timeIntervalSince1970 - 1_795_002_600.42) < 1)
    }

    @Test func mapsOpusAndSonnetWhenPresent() {
        let json = #"{"subscription_type":"max","rate_limits_available":true,"rate_limits":{"five_hour":null,"seven_day":{"utilization":10,"resets_at":"2026-11-23T08:00:00Z"},"seven_day_opus":{"utilization":5,"resets_at":"2026-11-23T08:00:00Z"},"seven_day_sonnet":{"utilization":7,"resets_at":"2026-11-23T08:00:00Z"}}}"#
        let usage = ClaudeLimitsClient.parse(Data(json.utf8))
        #expect(usage.windows.map(\.title) == ["Weekly limit", "Weekly · Opus", "Weekly · Sonnet"])
        #expect(usage.windows.allSatisfy { $0.windowMinutes == 10080 })
        #expect(usage.plan == "max")
    }

    @Test func dropsWindowsWithoutResetOrUtilization() {
        let json = #"{"rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":null,"resets_at":"2026-11-18T11:50:00Z"},"seven_day":{"utilization":10,"resets_at":null}}}"#
        let usage = ClaudeLimitsClient.parse(Data(json.utf8))
        #expect(usage.available && usage.windows.isEmpty && usage.plan == nil)
    }

    @Test func signedOutWhenLimitsUnavailableOrMissing() {
        #expect(!ClaudeLimitsClient.parse(Data(#"{"subscription_type":null,"rate_limits_available":false,"rate_limits":null}"#.utf8)).available)
        #expect(!ClaudeLimitsClient.parse(Data(#"{"subscription_type":"pro"}"#.utf8)).available)
        #expect(!ClaudeLimitsClient.parse(Data("not json".utf8)).available)
        #expect(!ClaudeLimitsClient.parse(Data()).available)
    }

    @Test func readsUsageReplyAfterUnrelatedLines() {
        let lines = [
            #"{"type":"system","subtype":"init","session_id":"x"}"#,
            "not json at all",
            #"{"type":"control_response","response":{"subtype":"success","request_id":"init","response":{}}}"#,
            #"{"type":"assistant","message":{}}"#,
            #"{"type":"control_response","response":{"subtype":"success","request_id":"usage","response":\#(full)}}"#,
        ]
        guard case .payload(let data)? = ClaudeLimitsClient.reply(fromLines: lines) else { Issue.record("no payload"); return }
        #expect(ClaudeLimitsClient.parse(data).windows.count == 2)
        // Not answered yet.
        #expect(ClaudeLimitsClient.reply(fromLines: Array(lines.prefix(4))) == nil)
        #expect(ClaudeLimitsClient.reply(fromLines: []) == nil)
    }

    @Test func failureSubtypeIsFailure() {
        let line = #"{"type":"control_response","response":{"subtype":"error","request_id":"usage","error":"Unsupported control request subtype: get_usage"}}"#
        #expect(ClaudeLimitsClient.reply(fromLines: [line]) == .failure)
    }

    @Test func parsesBothTimestampForms() {
        let a = ClaudeLimitsClient.date("2026-11-18T11:50:00Z")
        let b = ClaudeLimitsClient.date("2026-11-18T11:50:00.5+00:00")
        let c = ClaudeLimitsClient.date("2026-11-18T13:50:00+02:00")
        #expect(a != nil && b != nil)
        #expect(a == c)
        #expect(ClaudeLimitsClient.date("nope") == nil)
    }

    @Test func liveLimitsReplaceClaudeOnlyWhenFresh() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let local = RateWindow(usedPercent: 1, windowMinutes: 300, resetsAt: now)
        let live = [RateWindow(usedPercent: 49, windowMinutes: 300, resetsAt: now.addingTimeInterval(3600)),
                    RateWindow(usedPercent: 32, windowMinutes: 10080, resetsAt: now.addingTimeInterval(86400))]
        // A window that reset since the fetch is dropped.
        let partlyOver = ClaudeLiveLimits.merge(AgentUsageSample(agents: [AgentSummary(agent: .claude)]),
                                                live: [live[1], RateWindow(usedPercent: 90, windowMinutes: 300, resetsAt: now)],
                                                fetchedAt: now.addingTimeInterval(-60), now: now)
        #expect(partlyOver.agents[0].limits == [live[1]])
        var sample = AgentUsageSample(scanned: true)
        sample.agents = [AgentSummary(agent: .claude, limits: [local]), AgentSummary(agent: .codex, limits: [local])]

        let fresh = ClaudeLiveLimits.merge(sample, live: live, fetchedAt: now.addingTimeInterval(-60), now: now)
        #expect(fresh.agents[0].limits == live)
        #expect(fresh.agents[1].limits == [local])

        let stale = ClaudeLiveLimits.merge(sample, live: live, fetchedAt: now.addingTimeInterval(-16 * 60), now: now)
        #expect(stale == sample)
        #expect(ClaudeLiveLimits.merge(sample, live: [], fetchedAt: now, now: now) == sample)
        #expect(ClaudeLiveLimits.merge(sample, live: live, fetchedAt: nil, now: now) == sample)
    }
}
