import Foundation
import Testing
@testable import VibeCheck

/// Deck home: the summary card's facts and the tiles' second lines.
struct DeckSummaryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func window(used: Double, minutes: Int = 300, resetsIn: TimeInterval) -> RateWindow {
        RateWindow(usedPercent: used, windowMinutes: minutes, resetsAt: now.addingTimeInterval(resetsIn))
    }

    // MARK: Tightest limit

    @Test func tightestLimitPicksLeastLeftAcrossAgents() {
        let agents = [
            AgentSummary(agent: .claude, limits: [window(used: 40, resetsIn: 3600), window(used: 70, minutes: 10080, resetsIn: 86_400)]),
            AgentSummary(agent: .codex, limits: [window(used: 85, resetsIn: 7200)]),
        ]
        let tightest = DeckFacts.tightestLimit(agents)
        #expect(tightest?.agent == .codex)
        #expect(tightest?.window.leftPercent == 15)
    }

    @Test func tightestLimitTieGoesToEarliestReset() {
        let agents = [
            AgentSummary(agent: .claude, limits: [window(used: 50, resetsIn: 7200)]),
            AgentSummary(agent: .copilot, limits: [window(used: 50, resetsIn: 600)]),
        ]
        #expect(DeckFacts.tightestLimit(agents)?.agent == .copilot)
    }

    @Test func tightestLimitNilWithoutLimits() {
        #expect(DeckFacts.tightestLimit([]) == nil)
        #expect(DeckFacts.tightestLimit([AgentSummary(agent: .claude)]) == nil)
    }

    // MARK: Facts and hide rules

    @Test func noDataHidesTheCard() {
        #expect(DeckFacts.facts(uptime: 0, topApp: nil, energyLeader: nil, limit: nil, now: now).isEmpty)
    }

    @Test func factsWithoutDataAreHidden() {
        // Idle top app (< 1%), zero energy and a too-fresh uptime all count as no data.
        let facts = DeckFacts.facts(uptime: 30, topApp: ("Finder", 0.4), energyLeader: ("Safari", 0), limit: nil, now: now)
        #expect(facts.isEmpty)
        let some = DeckFacts.facts(uptime: 3 * 3600 + 5 * 60, topApp: nil, energyLeader: ("Safari", 1.25), limit: nil, now: now)
        #expect(some.map(\.kind) == [.uptime, .energy])
    }

    @Test func allFourFactsInOrderWithModules() {
        let limit = (agent: AgentKind.claude, window: window(used: 10, resetsIn: 3 * 3600))
        let facts = DeckFacts.facts(uptime: 2 * 86_400 + 4 * 3600, topApp: ("Google Chrome", 46.4),
                                    energyLeader: ("Xcode", 12.34), limit: limit, now: now)
        #expect(facts.map(\.kind) == [.uptime, .topApp, .energy, .limit])
        #expect(facts.map(\.module) == [.cpu, .cpu, .battery, .agents])
        #expect(facts[0].value == "2d 4h")
        #expect(facts[1].value == "Google Chrome" && facts[1].detail == "46% CPU")
        #expect(facts[2].value == "Xcode" && facts[2].detail == "12.3 Wh so far")
        #expect(facts[3].value == "90% left")
        // Slow pace: lasts until the reset, so no "runs out" time.
        #expect(facts[3].detail == "Claude Code, 5-hour limit")
        #expect(Set(facts.map(\.id)).count == facts.count)
    }

    @Test func limitFactSaysWhenItRunsOut() throws {
        // 2 h into a 5-hour window at 80% used: 40%/h, the last 20% lasts 30 min, before the reset.
        let w = window(used: 80, resetsIn: 3 * 3600)
        let runsOut = try #require(w.runsOutAt(now: now))
        let fact = DeckFacts.facts(uptime: 0, topApp: nil, energyLeader: nil, limit: (.claude, w), now: now).first
        #expect(fact?.value == "20% left")
        #expect(fact?.detail == "5-hour limit, runs out ~\(w.runOutTimeText(runsOut, now: now))")
        #expect(fact?.spoken.hasPrefix("Tightest limit: 20% left") == true)
    }

    @Test func shortNameKeepsRoomForTheNumber() {
        #expect(DeckFacts.shortName("Chrome", max: 11) == "Chrome")
        #expect(DeckFacts.shortName("Google Chrome Helper", max: 11) == "Google Chr…")
        #expect(DeckFacts.shortName("Google Chrome Helper", max: 11).count == 11)
        #expect(DeckFacts.shortName("  Safari ", max: 11) == "Safari")
    }

    // MARK: Tile notes

    @Test func appNoteAndCPUText() {
        #expect(TileContent.appNote("Chrome", TileContent.cpuText(46.4)) == "Chrome 46%")
        #expect(TileContent.appNote("Visual Studio Code", "7.0 GB") == "Visual Stu… 7.0 GB")
        #expect(TileContent.cpuText(212.6) == "213%")
        #expect(TileContent.cpuText(-1) == "0%")
    }

    @Test func topMemoryTrackSkipsStaleAndEmpty() {
        let fresh = AppMemoryTrack(name: "Chrome", samples: [AppMemorySample(date: now.addingTimeInterval(-30), footprint: 7e9, processCount: 20)])
        let small = AppMemoryTrack(name: "Mail", samples: [AppMemorySample(date: now.addingTimeInterval(-30), footprint: 1e9, processCount: 2)])
        let stale = AppMemoryTrack(name: "Old", samples: [AppMemorySample(date: now.addingTimeInterval(-3600), footprint: 9e9, processCount: 1)])
        let tracks: [AppMemoryKey: AppMemoryTrack] = [
            AppMemoryKey(pid: 1, startTime: 1): fresh, AppMemoryKey(pid: 2, startTime: 2): small, AppMemoryKey(pid: 3, startTime: 3): stale,
        ]
        #expect(TileContent.topMemoryTrack(tracks, now: now)?.name == "Chrome")
        #expect(TileContent.topMemoryTrack([AppMemoryKey(pid: 3, startTime: 3): stale], now: now) == nil)
        #expect(TileContent.topMemoryTrack([:], now: now) == nil)
    }

    @Test func networkNoteAddsLinkName() {
        #expect(TileContent.networkNote(upload: 340 * 1024, link: "Wi-Fi") == "↑ 340K · Wi-Fi")
        #expect(TileContent.networkNote(upload: 0, link: nil) == "↑ 0K")
        #expect(TileContent.networkNote(upload: 0, link: "") == "↑ 0K")
    }

    @Test func sensorNoteFallsBackFromFanToThermalToName() {
        #expect(TileContent.sensorNote(fanRPM: 2412.4, thermal: .nominal, hottestName: "SSD") == "Fan 2412 rpm")
        #expect(TileContent.sensorNote(fanRPM: 0, thermal: .nominal, hottestName: "SSD") == "No throttling")
        #expect(TileContent.sensorNote(fanRPM: nil, thermal: .fair, hottestName: nil) == "No throttling")
        #expect(TileContent.sensorNote(fanRPM: nil, thermal: .serious, hottestName: nil) == "Throttling")
        #expect(TileContent.sensorNote(fanRPM: nil, thermal: .critical, hottestName: nil) == "Throttling")
        #expect(TileContent.sensorNote(fanRPM: nil, thermal: nil, hottestName: "CPU / SoC (hottest)") == "CPU / SoC")
        #expect(TileContent.sensorNote(fanRPM: nil, thermal: nil, hottestName: nil) == nil)
        #expect(TileContent.shortSensorName("SSD") == "SSD")
        #expect(TileContent.shortSensorName("(odd)") == "(odd)")
    }

    @Test func batteryDetailAddsWatts() {
        #expect(TileContent.batteryDetail(state: "Charging", watts: 28.4) == "Charging · 28 W")
        #expect(TileContent.batteryDetail(state: "On battery", watts: -9.42) == "On battery · 9.4 W")
        #expect(TileContent.batteryDetail(state: "On power", watts: 0.2) == "On power")
        #expect(TileContent.batteryDetail(state: "On battery", watts: nil) == "On battery")
    }
}
