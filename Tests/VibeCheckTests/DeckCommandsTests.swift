import Foundation
import Testing
@testable import VibeCheck

@MainActor
struct DeckCommandsTests {
    private func command(_ title: String, _ keywords: String = "") -> DeckCommand {
        DeckCommand(id: title, title: title, symbol: "circle", keywords: keywords) {}
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
}
