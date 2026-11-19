import SwiftUI
import Testing
@testable import VibeCheck

@Suite struct RingSymbolTests {
    @Test func namesMatchTheAssetCatalog() throws {
        for vibe in [Vibe.vibing, .mid, .cooked] {
            let name = RingSymbol.name(vibe)
            let svg = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Resources/Symbols.xcassets/\(name).symbolset/\(name).svg")
            #expect(FileManager.default.fileExists(atPath: svg.path), "missing \(svg.path)")
        }
    }

    @Test func weightFollowsTheStrokeRatio() {
        #expect(RingSymbol.weight(lineWidth: 2.25, size: 16) == .regular)  // menu bar
        #expect(RingSymbol.weight(lineWidth: 3.5, size: 30) == .light)     // deck header
    }

    @Test func fallsBackToDrawnShapesOutsideTheApp() {
        // `swift test` has no Assets.car, so the drawn ring must be used.
        #expect(!RingSymbol.isAvailable)
    }
}
