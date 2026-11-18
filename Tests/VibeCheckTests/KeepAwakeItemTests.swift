import Foundation
import Testing
@testable import VibeCheck

@MainActor
struct KeepAwakeItemTests {
    @Test func menuOffersStartAndEveryOptionWhenIdle() {
        guard !KeepAwake.shared.isActive else { return }   // don't disturb a running session
        let titles = KeepAwakeMenu().titles()
        #expect(titles.first?.hasPrefix("Start (") == true)
        #expect(titles.contains("Until"))
        #expect(titles.contains("Focus for 25 Minutes") && titles.contains("Focus for 90 Minutes"))
        #expect(titles.contains("Keep the Display On"))
        #expect(titles.last == "Keep Awake Settings…")
    }

    @Test func standaloneItemHidesTheExtraCup() {
        let settings = AppSettings.shared
        let saved = settings.keepAwakeMenuBarItem
        defer { settings.keepAwakeMenuBarItem = saved }
        settings.keepAwakeMenuBarItem = true
        #expect(!AwakeCup.isShown(settings))     // never two cups, running or not
    }
}
