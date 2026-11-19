import Foundation
import Testing
@testable import VibeCheck

@MainActor
struct ItemOrderTests {
    @Test func autosaveNamesChangeWithTheGeneration() {
        #expect(AppSettings.autosaveName("cpu", generation: 0) == "vibecheck.cpu")   // unchanged for existing installs
        #expect(AppSettings.autosaveName("cpu", generation: 3) == "vibecheck.cpu.g3")
        #expect(AppSettings.autosaveName("vibe", generation: 1) == "vibecheck.vibe.g1")
    }

    @Test func reorderingBumpsTheGenerationOnlyWhenTheOrderChanges() {
        let settings = AppSettings.shared
        let order = settings.moduleOrder, generation = settings.statusItemGeneration
        defer {
            if let index = settings.moduleOrder.firstIndex(of: order[0]), index != 0 {
                settings.moveModules(from: [index], to: 0)
            }
            settings.statusItemGeneration = generation
        }
        settings.moveModules(from: [0], to: 2)
        #expect(settings.statusItemGeneration == generation + 1)
        settings.moveModules(from: [1], to: 1)                                       // no-op move
        #expect(settings.statusItemGeneration == generation + 1)
    }
}
