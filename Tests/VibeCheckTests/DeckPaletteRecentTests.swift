import Foundation
import Testing
@testable import VibeCheck

@MainActor
struct DeckPaletteRecentTests {
    private func command(_ id: String, _ title: String) -> DeckCommand {
        DeckCommand(id: id, title: title, symbol: "circle") {}
    }

    @Test func recentListMovesToFrontDedupesAndCaps() {
        var list: [String] = []
        for i in 0..<12 { list = RecentCommands.updated(list, with: "c\(i)") }
        #expect(list.count == RecentCommands.capacity)
        #expect(list.first == "c11")
        list = RecentCommands.updated(list, with: "c5")
        #expect(list.first == "c5" && list.filter { $0 == "c5" }.count == 1)
    }

    @Test func emptyQueryFloatsRecentCommands() {
        let all = [command("a", "Alpha"), command("b", "Beta"), command("c", "Gamma")]
        let result = DeckCommands.filter(all, query: "", recent: ["c", "b"])
        #expect(result.map(\.id) == ["c", "b", "a"])
    }

    @Test func recentBreaksTiesButNotScores() {
        let all = [command("a", "Open CPU"), command("b", "Open Memory"), command("c", "Reopen")]
        let result = DeckCommands.filter(all, query: "open", recent: ["b"])
        #expect(result.map(\.id) == ["b", "a", "c"])   // both prefix matches: recent first; "Reopen" scores lower
    }

    @Test func recordedIDsRoundTripThroughDefaults() throws {
        let suite = "deck-recent-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecentCommands.record("x", defaults: defaults)
        RecentCommands.record("y", defaults: defaults)
        #expect(RecentCommands.load(defaults) == ["y", "x"])
    }

    @Test func emptyTrashIsAConfirmedCommandWithoutProcessesOrChips() {
        let model = DeckModel()
        let commands = DeckCommands.all(model: model, settings: AppSettings.shared)
        let trash = commands.first { $0.id == "trash.empty" }
        #expect(trash?.confirm == true)
        #expect(commands.contains { $0.id.hasPrefix("alert.") } == !AppSettings.shared.alertRules.isEmpty)
    }

    @Test func hintShowsOncePerVersion() {
        #expect(!DeckHint.shouldShow(current: "1.6", seen: nil))
        #expect(DeckHint.shouldShow(current: "1.6", seen: "1.5"))
        #expect(!DeckHint.shouldShow(current: "1.6", seen: "1.6"))
        #expect(!DeckHint.shouldShow(current: nil, seen: nil))
    }

    @Test func cupTooltipNamesTheHoldDial() {
        #expect(AwakeMenuButton.tooltip("Keep your Mac awake").contains("Hold to set a time."))
    }

    @Test func shakeIsThreePointsAndSettlesAtZero() {
        #expect(ShakeEffect.amount == 3)
        #expect(abs(ShakeEffect.duration - 0.24) < 0.0001)
    }
}
