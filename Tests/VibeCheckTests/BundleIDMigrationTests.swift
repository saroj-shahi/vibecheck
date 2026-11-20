import Foundation
import Testing
@testable import VibeCheck

struct BundleIDMigrationTests {
    private func suite() -> (UserDefaults, String) {
        let name = "vibecheck.test.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func copiesOldSettingsOnce() {
        let (d, name) = suite()
        defer { d.removePersistentDomain(forName: name) }
        let old: [String: Any] = ["enabledModules": ["cpu", "clock"], "refreshInterval": 5.0]
        #expect(BundleIDMigration.run(defaults: d, legacy: { old }))
        #expect(d.stringArray(forKey: "enabledModules") == ["cpu", "clock"])
        #expect(d.double(forKey: "refreshInterval") == 5)
        #expect(d.bool(forKey: BundleIDMigration.doneKey))
        // A second launch doesn't copy again, even if the old domain changed.
        d.set(["memory"], forKey: "enabledModules")
        #expect(!BundleIDMigration.run(defaults: d, legacy: { old }))
        #expect(d.stringArray(forKey: "enabledModules") == ["memory"])
    }

    @Test func keepsSettingsAlreadyUnderTheNewID() {
        let (d, name) = suite()
        defer { d.removePersistentDomain(forName: name) }
        d.set(["gpu"], forKey: "enabledModules")
        #expect(!BundleIDMigration.run(defaults: d, legacy: { ["enabledModules": ["cpu"]] }))
        #expect(d.stringArray(forKey: "enabledModules") == ["gpu"])
        #expect(d.bool(forKey: BundleIDMigration.doneKey))
    }

    @Test func freshInstallHasNothingToCopy() {
        let (d, name) = suite()
        defer { d.removePersistentDomain(forName: name) }
        #expect(!BundleIDMigration.run(defaults: d, legacy: { nil }))
        #expect(d.object(forKey: "enabledModules") == nil)
        #expect(d.bool(forKey: BundleIDMigration.doneKey))
    }
}
