import Foundation
import Testing
@testable import VibeCheck

struct AppMemoryHistoryTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let gb = 1_000_000_000.0

    private func samples(_ points: [(minAgo: Double, gb: Double)]) -> [AppMemorySample] {
        points.map { AppMemorySample(date: now.addingTimeInterval(-$0.minAgo * 60), footprint: $0.gb * gb, processCount: 3) }
    }

    @Test func growthNeedsHistory() {
        #expect(AppMemoryHistory.growth([], now: now) == nil)
        #expect(AppMemoryHistory.growth(samples([(0, 5)]), now: now) == nil)
        #expect(AppMemoryHistory.growth(samples([(10, 4), (0, 6)]), now: now) == nil)
    }

    @Test func growthOverAnHour() throws {
        let s = samples([(64, 1), (60, 2), (30, 3), (0, 4.4)])
        let g = try #require(AppMemoryHistory.growth(s, now: now))
        #expect(abs(g.bytes - 2.4 * gb) < 1)
        #expect(g.minutes == 60)
    }

    @Test func growthReportsActualSpanAndShrink() throws {
        let g = try #require(AppMemoryHistory.growth(samples([(30, 5), (0, 3)]), now: now))
        #expect(g.minutes == 30)
        #expect(g.bytes < 0)
    }

    @Test func topSelectionAndTracking() {
        let groups = (1...20).map { AppMemoryGroup(pid: Int32($0), startTime: 1, name: "a\($0)", footprint: Double($0), processCount: 1) }
        #expect(AppMemoryHistory.topByFootprint(groups, limit: 3).map(\.pid) == [20, 19, 18])
        var h = AppMemoryHistory()
        h.record(groups, now: now)
        #expect(h.tracks.count == 15)
        // Tracked app stays while alive even if it drops out of the top; gone apps are dropped.
        let next = groups.filter { $0.pid != 20 }.map {
            AppMemoryGroup(pid: $0.pid, startTime: 1, name: $0.name, footprint: $0.pid == 6 ? 0.1 : $0.footprint, processCount: 1)
        }
        h.record(next, now: now.addingTimeInterval(60))
        #expect(h.tracks[AppMemoryKey(pid: 6, startTime: 1)] != nil)
        #expect(h.tracks[AppMemoryKey(pid: 20, startTime: 1)] == nil)
        #expect(h.tracks[AppMemoryKey(pid: 1, startTime: 1)] == nil)
        // A reused pid with a new start time is a new app.
        h.record([AppMemoryGroup(pid: 6, startTime: 2, name: "new", footprint: 1, processCount: 1)], now: now.addingTimeInterval(120))
        #expect(h.tracks.count == 1)
        #expect(h.tracks.values.first?.samples.count == 1)
    }

    @Test func scanCostAndContent() {
        let start = Date()
        let groups = AppMemoryHistory.scan()
        let ms = Date().timeIntervalSince(start) * 1000
        print("AppMemoryHistory.scan: \(groups.count) apps in \(Int(ms)) ms")
        #expect(!groups.isEmpty)
    }

    @Test func memoryVerdictSentences() {
        let warn = VibeInput(memoryPressure: .warning)
        let grew = ("Chrome", 6 * gb, 14, Optional(2.4 * gb), Optional(60))
        #expect(VibeScore.verdict(for: .mid, input: warn, topApp: ("Xcode", 90), memoryApp: grew)
                == "Kinda mid: memory is getting tight. Chrome (14 processes) grew \(Fmt.bytes(2.4 * gb)) in the last hour.")
        #expect(VibeScore.verdict(for: .mid, input: warn, topApp: nil, memoryApp: ("Chrome", 6 * gb, 14, 2.4 * gb, 42))
                .hasSuffix("Chrome (14 processes) grew \(Fmt.bytes(2.4 * gb)) in the last 42 min."))
        #expect(VibeScore.verdict(for: .mid, input: warn, topApp: nil, memoryApp: ("Slack", 3 * gb, 1, 1 * gb, 60))
                .hasSuffix("Slack grew \(Fmt.bytes(1 * gb)) in the last hour."))
        let flat = VibeScore.verdict(for: .cooked, input: VibeInput(memoryPressure: .critical), topApp: ("Xcode", 90),
                                     memoryApp: ("Chrome", 6 * gb, 14, 0.1 * gb, 60))
        #expect(flat == "Your Mac is cooked: memory pressure is critical. Chrome is using the most memory, \(Fmt.bytes(6 * gb)).")
        #expect(VibeScore.verdict(for: .mid, input: warn, topApp: nil, memoryApp: ("Chrome", 6 * gb, 14, nil, nil))
                .hasSuffix("Chrome is using the most memory, \(Fmt.bytes(6 * gb))."))
    }

    @Test func cpuCulpritKeepsLoudestLine() {
        let cpu = VibeInput(cpuRecent: 0.7)
        #expect(VibeScore.verdict(for: .mid, input: cpu, topApp: ("Xcode", 180), memoryApp: ("Chrome", 6 * gb, 14, 2.4 * gb, 60))
                == VibeScore.verdict(for: .mid, input: cpu, topApp: ("Xcode", 180)))
        #expect(VibeScore.verdict(for: .mid, input: cpu, topApp: ("Xcode", 180)).hasSuffix("Xcode is the loudest at 180% CPU."))
        #expect(VibeScore.verdict(for: .vibing, input: VibeInput(), topApp: ("Finder", 1), memoryApp: ("Chrome", gb, 2, nil, nil))
                == "Your Mac is vibing. Nothing's working hard.")
    }
}

struct AppMemoryPauseTests {
    @Test func aLongGapStartsTheHistoryOver() {
        var history = AppMemoryHistory()
        let start = Date()
        let group = AppMemoryGroup(pid: 42, startTime: 1, name: "Chrome", footprint: 1e9, processCount: 3)
        history.record([group], now: start)
        history.record([group], now: start.addingTimeInterval(60))
        #expect(history.tracks.values.first?.samples.count == 2)
        history.record([group], now: start.addingTimeInterval(60 + 40 * 60)) // a 40 min sleep
        #expect(history.tracks.values.first?.samples.count == 1)
    }
}
