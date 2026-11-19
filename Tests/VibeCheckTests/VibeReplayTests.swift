import Testing
import Foundation
@testable import VibeCheck

@MainActor
struct VibeReplayTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vc-\(UUID().uuidString).json")
    }

    @Test func recordsAndPersistsEpisode() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = VibeReplayStore(fileURL: url)
        let t0 = Date()
        store.observe(level: .mid, culprit: .cpu, process: nil, at: t0)
        store.observe(level: .cooked, culprit: .cpu, process: "Chrome Helper", at: t0.addingTimeInterval(30))
        store.observe(level: .vibing, culprit: nil, process: nil, at: t0.addingTimeInterval(90))
        #expect(store.episodes.count == 1)
        #expect(store.episodes[0].worst == Vibe.cooked.rawValue)
        #expect(store.episodes[0].process == "Chrome Helper")
        #expect(VibeReplayStore(fileURL: url).episodes.count == 1)
    }

    @Test func weeklySummary() {
        let now = Date()
        let t = now.timeIntervalSince1970
        let cooked = VibeEpisode(start: t - 1000, end: t - 900, worst: 2, culprit: "cpu", process: "Chrome Helper")
        #expect(VibeReplayStore.weeklySummary([], now: now) == "Your Mac has been vibing all week.")
        #expect(VibeReplayStore.weeklySummary([cooked, cooked, cooked, cooked], now: now)
                == "Chrome Helper cooked your Mac 4 times this week.")
        #expect(VibeReplayStore.weeklySummary([cooked], now: now) == "Chrome Helper cooked your Mac once this week.")
        let old = VibeEpisode(start: t - 9 * 86_400, end: t - 9 * 86_400 + 60, worst: 2, culprit: nil, process: nil)
        #expect(VibeReplayStore.weeklySummary([old], now: now) == "Your Mac has been vibing all week.")
    }

    @Test func segmentsCoverTheDay() {
        let now = Date()
        let t = now.timeIntervalSince1970
        let e = VibeEpisode(start: t - 43_200, end: t - 28_800, worst: 1, culprit: nil, process: nil)
        let segs = VibeReplayStore.segments([e], now: now)
        #expect(segs.count == 3)
        #expect(segs[0].vibe == .vibing && segs[1].vibe == .mid && segs[2].vibe == .vibing)
        #expect(abs(segs[1].start - 0.5) < 0.001 && abs(segs[1].end - 0.6667) < 0.001)
    }

    @Test func batteryLogRateAndHealth() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = BatteryLogStore(fileURL: url)
        var s = BatterySample(); s.present = true; s.percent = 0.8; s.health = 0.9
        let t0 = Date()
        store.record(s, at: t0)
        store.record(s, at: t0.addingTimeInterval(120))
        #expect(store.points.count == 1)
        s.percent = 0.7
        store.record(s, at: t0.addingTimeInterval(180))
        #expect(store.points.count == 2)
        store.record(s, at: t0.addingTimeInterval(180 + 900))
        #expect(store.points.count == 3)
        #expect(BatteryLogStore.healthTrend(store.points).count == 1)
    }
}
