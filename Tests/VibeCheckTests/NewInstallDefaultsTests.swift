import Foundation
import Testing
@testable import VibeCheck

@MainActor
struct NewInstallDefaultsTests {
    private func suite() -> (UserDefaults, String) {
        let name = "vibecheck.test.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func freshInstallGetsSixTiles() {
        let (d, name) = suite()
        defer { d.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: d)
        #expect(s.enabledModules == [.cpu, .memory, .network, .sensors, .battery, .agents])
    }

    @Test func existingChoicesAreKept() {
        let (d, name) = suite()
        defer { d.removePersistentDomain(forName: name) }
        d.set(["cpu", "clock", "weather"], forKey: "enabledModules")
        d.set(Module.allCases.map(\.rawValue), forKey: "knownModules")
        let s = AppSettings(defaults: d)
        #expect(s.enabledModules == [.cpu, .clock, .weather])
    }
}
