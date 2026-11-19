import Foundation
import Testing
@testable import VibeCheck

@MainActor
struct IntentsTests {
    @Test func everyModuleCanBeOpenedFromShortcuts() {
        let options = Set(DeckModuleOption.allCases.map(\.module))
        #expect(options == Set(Module.allCases))
        #expect(DeckModuleOption.caseDisplayRepresentations.count == Module.allCases.count)
        #expect(StatKind.caseDisplayRepresentations.count == StatKind.allCases.count)
    }

    @Test func statsReadAsNumbersAndSentences() {
        let stats = SystemStats()
        let cpu = StatReading.read(.cpu, stats: stats)
        #expect(cpu?.value == 0)
        #expect(cpu?.text == "CPU is at 0%.")
        #expect(StatReading.read(.download, stats: stats)?.text == "You're offline.") // no sample yet = no interface
        #expect(StatReading.read(.temperature, stats: stats) == nil)

        var agents = AgentUsageSample(scanned: true)
        #expect(StatReading.read(.agentTokens, stats: stats, agents: agents) == nil) // no agent logs
        agents.agents = [AgentSummary(agent: .claude)]
        agents.today = TokenCounts(input: 1_000, output: 200_000, cacheWrite: 0, cacheRead: 2_000_000)
        let tokens = StatReading.read(.agentTokens, stats: stats, agents: agents)
        #expect(tokens?.value == 2_201_000)
        #expect(tokens?.text == "Your coding agents used 2.2M tokens today.")
    }
}
