import AppKit
import SwiftUI
import Testing
@testable import VibeCheck

@MainActor
struct DeckTests {
    @Test func arrowKeysMoveAroundTheGridWithoutWrapping() {
        // 8 tiles in 3 columns:  0 1 2 / 3 4 5 / 6 7
        #expect(DeckModel.move(nil, .right, count: 8) == 0)        // first press lands on the first tile
        #expect(DeckModel.move(0, .left, count: 8) == 0)
        #expect(DeckModel.move(2, .right, count: 8) == 3)
        #expect(DeckModel.move(7, .right, count: 8) == 7)
        #expect(DeckModel.move(1, .down, count: 8) == 4)
        #expect(DeckModel.move(5, .down, count: 8) == 5)           // nothing below 5
        #expect(DeckModel.move(4, .up, count: 8) == 1)
        #expect(DeckModel.move(1, .up, count: 8) == 1)
        #expect(DeckModel.move(nil, .down, count: 0) == nil)
    }

    @Test func openingAModuleFocusesItsTileAndStaggersByDistance() {
        let model = DeckModel()
        model.modules = [.cpu, .gpu, .memory, .network, .disk, .sensors]
        var routes: [DeckRoute] = []
        model.onRouteChange = { routes.append($0) }

        model.go(.module(.network), animated: false)  // index 3: row 1, column 0
        #expect(model.route == .module(.network))
        #expect(model.focusIndex == 3)
        #expect(routes == [.module(.network)])

        if !Deck.reduceMotion {
            #expect(model.staggerDelay(for: 3) == 0)
            #expect(abs(model.staggerDelay(for: 4) - 0.025) < 1e-9)   // one step away
            #expect(abs(model.staggerDelay(for: 2) - 0.075) < 1e-9)   // up one, right two
        }

        model.go(.module(.network), animated: false)  // same route: no duplicate callback
        #expect(routes.count == 1)
    }

    @Test func tilesHaveContentForEveryModule() {
        let stats = SystemStats()
        for module in Module.allCases {
            let content = TileContent.make(module, stats: stats, settings: AppSettings.shared)
            #expect(!content.value.isEmpty, "\(module)")
            #expect(!content.spoken.isEmpty, "\(module)")
        }
    }

    @Test func deckHomeAndDetailHaveSensibleHeights() {
        let stats = SystemStats()
        let model = DeckModel()
        model.modules = [.cpu, .gpu, .memory, .network, .disk, .sensors]
        func height(_ view: some View) -> CGFloat {
            NSHostingView(rootView: view.environment(stats).environment(AppSettings.shared).environment(model))
                .fittingSize.height
        }
        let home = height(DeckHome())
        let cpu = height(ModulePanel(module: .cpu).environment(\.deckShowsBack, true))
        print("deck heights → home \(Int(home)), cpu detail \(Int(cpu))")
        #expect(home > 150 && home < 400)
        #expect(cpu > home)
    }
}

struct DeckPlacementTests {
    // Geometry measured on a Mac with an external 1920×1080 display above the built-in one.
    let screen = NSRect(x: -44, y: 1169, width: 1920, height: 1080)
    let visible = NSRect(x: -44, y: 1169, width: 1920, height: 1050)

    @Test func buttonInTheMenuBarCounts() {
        // Status item windows here are 39 pt tall and poke above the screen; the button itself is inside.
        let button = NSRect(x: 817, y: 2224, width: 46, height: 22)
        #expect(DeckController.isInMenuBar(button, screen: screen, visible: visible))
    }

    @Test func unplacedOrOffscreenButtonsDoNot() {
        #expect(!DeckController.isInMenuBar(NSRect(x: 0, y: 0, width: 46, height: 22), screen: screen, visible: visible))
        #expect(!DeckController.isInMenuBar(NSRect(x: 817, y: 1500, width: 46, height: 22), screen: screen, visible: visible))
        #expect(!DeckController.isInMenuBar(NSRect(x: 3000, y: 2224, width: 46, height: 22), screen: screen, visible: visible))
    }
}
