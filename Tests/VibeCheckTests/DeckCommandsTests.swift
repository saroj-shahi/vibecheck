import Foundation
import Testing
@testable import VibeCheck

@MainActor
struct DeckCommandsTests {
    private func command(_ title: String, _ keywords: String = "") -> DeckCommand {
        DeckCommand(id: title, title: title, symbol: "circle", keywords: keywords) {}
    }

    @Test func actionsOfferTheMatchingSettingsPane() {
        let model = DeckModel()
        var withPane = command("Keep awake")
        withPane.settingsSection = .keepAwake
        #expect(DeckCommands.actions(for: withPane, model: model).map(\.title) == ["Run", "Open Keep Awake settings"])
        #expect(DeckCommands.actions(for: command("Mute the microphone"), model: model).map(\.title) == ["Run"])
    }

    @Test func actionsRunGoesThroughConfirmation() {
        let model = DeckModel()
        var ran = false
        let quit = DeckCommand(id: "quit", title: "Quit VibeCheck", symbol: "power", confirm: true) { ran = true }
        let run = DeckCommands.actions(for: quit, model: model)[0]
        #expect(run.title == "Quit VibeCheck")
        run.run()
        #expect(!ran && model.paletteConfirmID == "quit")   // first ↩ only arms it
    }

    @Test func movingTheSelectionClosesTheActions() {
        let model = DeckModel()
        model.openPalette()
        model.paletteActionsOpen = true
        model.paletteActionIndex = 1
        model.paletteIndex = 2
        #expect(!model.paletteActionsOpen)
        model.paletteActionsOpen = true
        #expect(model.paletteActionIndex == 0)
        model.typeInPalette("a")
        #expect(!model.paletteActionsOpen)
    }

    @Test func awakeDialSegments() {
        #expect(AwakeDial.segment(for: CGSize(width: 3, height: -5)) == nil)      // dead zone
        #expect(AwakeDial.segment(for: CGSize(width: 0, height: -30)) == 0)       // up: 15m
        #expect(AwakeDial.segment(for: CGSize(width: 30, height: 5)) == 1)        // right: 1h
        #expect(AwakeDial.segment(for: CGSize(width: -4, height: 30)) == 2)       // down: 4h
        #expect(AwakeDial.segment(for: CGSize(width: -30, height: 0)) == 3)       // left: until off
        #expect(AwakeDial.segment(for: CGSize(width: -20, height: -21)) == 0)     // up-left leans up
    }

    @Test func scoring() {
        #expect(DeckCommands.score("open", title: "Open CPU", keywords: "") == 400)        // title prefix
        #expect(DeckCommands.score("cpu", title: "Open CPU", keywords: "") == 300)         // word prefix
        #expect(DeckCommands.score("pen", title: "Open CPU", keywords: "") == 200)         // substring
        #expect(DeckCommands.score("caff", title: "Keep awake", keywords: "caffeinate") == 150)
        #expect(DeckCommands.score("ka", title: "Keep awake", keywords: "") == 100)        // initials
        #expect(DeckCommands.score("zzz", title: "Keep awake", keywords: "") == nil)
    }

    @Test func filterRanksAndLimits() {
        let list = [command("Mute the microphone", "audio"), command("Open Memory"), command("Open CPU"),
                    command("Quit VibeCheck", "exit")]
        #expect(DeckCommands.filter(list, query: "mem").map(\.title) == ["Open Memory"])
        #expect(DeckCommands.filter(list, query: "m").first?.title == "Mute the microphone")   // prefix beats word
        #expect(DeckCommands.filter(list, query: "  exit ").map(\.title) == ["Quit VibeCheck"])
        #expect(DeckCommands.filter(list, query: "").count == 4)
        let many = (0..<20).map { command("Item \($0)") }
        #expect(DeckCommands.filter(many, query: "").count == DeckCommands.limit)
        #expect(DeckCommands.filter(many, query: "item").count == DeckCommands.limit)
    }

    @Test func typedText() {
        func key(_ chars: String?, command: Bool = false) -> DeckController.KeyPress {
            .init(code: 0, characters: chars, command: command, windowNumber: 0)
        }
        #expect(DeckController.typedText(key("c")) == "c")
        #expect(DeckController.typedText(key("7")) == "7")
        #expect(DeckController.typedText(key("c", command: true)) == nil)
        #expect(DeckController.typedText(key(" ")) == nil)
        #expect(DeckController.typedText(key(" "), allowSpace: true) == " ")
        #expect(DeckController.typedText(key("\u{F700}")) == nil)   // up arrow
        #expect(DeckController.typedText(key("\r")) == nil)
        #expect(DeckController.typedText(key(nil)) == nil)
    }

    @Test func paletteStateInModel() {
        let model = DeckModel()
        #expect(!model.paletteOpen)
        model.openPalette("c")
        model.typeInPalette("p")
        #expect(model.paletteQuery == "cp")
        model.paletteIndex = 3
        model.deleteInPalette()
        #expect(model.paletteQuery == "c")
        #expect(model.paletteIndex == 0)
        model.closePalette()
        #expect(!model.paletteOpen)
    }

    @Test func quitNeedsASecondReturn() {
        let model = DeckModel()
        model.openPalette("q")
        var ran = 0
        let quit = DeckCommand(id: "quit", title: "Quit", symbol: "power", confirm: true) { ran += 1 }
        DeckCommands.activate(quit, model: model)
        #expect(ran == 0 && model.paletteConfirmID == "quit")
        model.typeInPalette("u")                        // any other key disarms it
        #expect(model.paletteConfirmID == nil)
        DeckCommands.activate(quit, model: model)
        DeckCommands.activate(quit, model: model)
        #expect(ran == 1)
        let plain = DeckCommand(id: "x", title: "X", symbol: "circle") { ran += 1 }
        DeckCommands.activate(plain, model: model)
        #expect(ran == 2)
    }

    @Test func routeChangeClosesPalette() {
        let model = DeckModel()
        model.modules = [.cpu, .gpu]
        model.openPalette("c")
        model.go(.module(.gpu), animated: false)
        #expect(!model.paletteOpen)
    }

    @Test func paletteSurfacesDeepSettingsControlsForQuery() {
        let suite = "DeckCommandsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let model = DeckModel()
        model.openPalette("notch")
        let all = DeckCommands.all(model: model, settings: settings)
        let filtered = DeckCommands.filter(all, query: "notch", recent: [])
        #expect(filtered.contains { $0.id == "settings.deep.menuBar.notch" && $0.subtitle != nil })
    }
}
