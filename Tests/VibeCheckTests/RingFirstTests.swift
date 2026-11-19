import Testing
import Foundation
@testable import VibeCheck

@MainActor
struct RingFirstTests {
    private func suite() -> (UserDefaults, String) {
        let name = "ringfirst-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func freshInstallIsRingOnly() {
        let (d, name) = suite(); defer { d.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: d)
        #expect(s.menuBar.style == .ring)
        #expect(s.menuBar.ringVisible)
        #expect(!s.keepAwake.menuBarItem)
        #expect(!s.enabledModules.isEmpty) // the deck keeps its tiles
    }

    @Test func existingInstallKeepsItsStyle() {
        let (d, name) = suite(); defer { d.removePersistentDomain(forName: name) }
        d.set(["cpu", "memory"], forKey: "enabledModules")
        #expect(AppSettings(defaults: d).menuBar.style == .combined)
        d.set("separate", forKey: "menuBarStyle")
        let s = AppSettings(defaults: d)
        #expect(s.menuBar.style == .separate)
        #expect(!s.menuBar.ringVisible == !s.menuBar.showVibeRing)
    }

    @Test func standaloneCupSettingIsKept() {
        let (d, name) = suite(); defer { d.removePersistentDomain(forName: name) }
        d.set(["cpu"], forKey: "enabledModules")
        d.set(true, forKey: "keepAwakeMenuBarItem")
        let s = AppSettings(defaults: d)
        #expect(s.keepAwake.menuBarItem)
        #expect(!AwakeCup.inRing(s))
    }

    @Test func verdictMentionsKeepAwake() {
        let on = StatusItemController.verdictText(for: .vibe, verdict: "All good.", keepAwake: true)
        #expect(on?.toolTip.contains("awake") == true)
        #expect(on?.accessibility.contains("awake") == true)
        #expect(StatusItemController.verdictText(for: .vibe, verdict: "All good.")?.toolTip == "All good.")
    }
}

@MainActor @Test func ringOnlyStyleShowsNoModuleNumbers() {
    let suite = "vc-ring-badge-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.menuBar.style = .ring
    #expect(settings.isEnabled(.cpu))
    #expect(!settings.showsInMenuBar(.cpu))
    settings.menuBar.style = .separate
    #expect(settings.showsInMenuBar(.cpu))
}
