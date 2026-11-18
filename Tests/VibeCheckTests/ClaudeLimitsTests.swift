import Foundation
import Testing
@testable import VibeCheck

struct ClaudeLimitsTests {
    let full = #"{"five_hour":{"utilization":49.0,"resets_at":"2026-11-18T11:50:00.123456+00:00"},"seven_day":{"utilization":32,"resets_at":"2026-11-23T08:00:00Z"},"seven_day_opus":{"utilization":5,"resets_at":"2026-11-23T08:00:00Z"}}"#

    @Test func parsesFullResponse() {
        let windows = ClaudeLimitsClient.parse(Data(full.utf8))
        #expect(windows.map(\.windowMinutes) == [300, 10080])
        #expect(windows.map(\.usedPercent) == [49, 32])
        #expect(abs(windows[0].resetsAt.timeIntervalSince1970 - 1_795_002_600.123) < 1)
        #expect(windows[1].resetsAt == Date(timeIntervalSince1970: 1_795_420_800))
    }

    @Test func toleratesMissingAndNullFields() {
        let json = #"{"five_hour":{"utilization":null,"resets_at":"2026-11-18T11:50:00Z"},"seven_day":{"utilization":10,"resets_at":"2026-11-23T08:00:00Z"}}"#
        let windows = ClaudeLimitsClient.parse(Data(json.utf8))
        #expect(windows.count == 1)
        #expect(windows[0].windowMinutes == 10080)
        // No reset time: dropped rather than shown with a made-up date.
        #expect(ClaudeLimitsClient.parse(Data(#"{"seven_day":{"utilization":10,"resets_at":null}}"#.utf8)).isEmpty)
        #expect(ClaudeLimitsClient.parse(Data(#"{"five_hour":null}"#.utf8)).isEmpty)
        #expect(ClaudeLimitsClient.parse(Data("{}".utf8)).isEmpty)
    }

    @Test func parsesBothTimestampForms() {
        let a = ClaudeLimitsClient.date("2026-11-18T11:50:00Z")
        let b = ClaudeLimitsClient.date("2026-11-18T11:50:00.5+00:00")
        let c = ClaudeLimitsClient.date("2026-11-18T13:50:00+02:00")
        #expect(a != nil && b != nil)
        #expect(a == c)
        #expect(ClaudeLimitsClient.date("nope") == nil)
    }

    @Test func garbageGivesNothing() {
        #expect(ClaudeLimitsClient.parse(Data("not json".utf8)).isEmpty)
        #expect(ClaudeLimitsClient.parse(Data("[1,2]".utf8)).isEmpty)
        #expect(ClaudeLimitsClient.parse(Data()).isEmpty)
    }

    @Test func readsTokenFromFixtureAndSkipsExpired() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let ok = Data(#"{"claudeAiOauth":{"accessToken":"fixture","expiresAt":2000000000}}"#.utf8)
        let old = Data(#"{"claudeAiOauth":{"accessToken":"fixture","expiresAt":1000}}"#.utf8)
        #expect(ClaudeLimitsClient.token(fromCredentials: ok, now: now) == "fixture")
        #expect(ClaudeLimitsClient.token(fromCredentials: old, now: now) == nil)
        #expect(ClaudeLimitsClient.token(fromCredentials: Data("{}".utf8), now: now) == nil)
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
