import Foundation
import Testing
@testable import VibeCheck

@MainActor @Suite struct StarPromptTests {
    private func makePrompt(_ choice: StarPrompt.Choice, opened: @escaping @MainActor (URL) -> Void) -> (StarPrompt, UserDefaults) {
        let defaults = UserDefaults(suiteName: "StarPromptTests-\(UUID().uuidString)")!
        let prompt = StarPrompt()
        prompt.defaults = defaults
        prompt.present = { choice }
        prompt.openURL = opened
        return (prompt, defaults)
    }

    @Test func dueOnlyAfterTwoDaysAndOnce() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        #expect(!StarPrompt.isDue(firstSeen: nil, shown: false, now: start))
        #expect(!StarPrompt.isDue(firstSeen: start, shown: false, now: start.addingTimeInterval(47 * 3600)))
        #expect(StarPrompt.isDue(firstSeen: start, shown: false, now: start.addingTimeInterval(48 * 3600)))
        #expect(!StarPrompt.isDue(firstSeen: start, shown: true, now: start.addingTimeInterval(72 * 3600)))
    }

    @Test func showsOnceAndOpensTheChosenLink() {
        var opened: [URL] = []
        let (prompt, defaults) = makePrompt(.support) { opened.append($0) }
        let start = Date(timeIntervalSince1970: 1_000_000)
        defaults.set(start, forKey: StarPrompt.firstSeenKey)
        prompt.now = { start.addingTimeInterval(3600) }
        prompt.showIfDue()
        #expect(opened.isEmpty)
        prompt.now = { start.addingTimeInterval(3 * 24 * 3600) }
        prompt.showIfDue()
        prompt.showIfDue()
        #expect(opened == [StarPrompt.supportURL])
        #expect(defaults.bool(forKey: StarPrompt.shownKey))
    }

    @Test func notNowNeverAsksAgain() {
        var asked = 0
        let (prompt, defaults) = makePrompt(.later) { _ in Issue.record("nothing should open") }
        prompt.present = { asked += 1; return .later }
        defaults.set(Date(timeIntervalSince1970: 0), forKey: StarPrompt.firstSeenKey)
        prompt.showIfDue()
        prompt.showIfDue()
        #expect(asked == 1)
    }
}
