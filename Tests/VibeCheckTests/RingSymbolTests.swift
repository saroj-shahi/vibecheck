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

@Suite struct RingWobbleTests {
    @Test func stillWhileVibing() {
        #expect(!RingWobble.isWobbling(.vibing))
        for theta in stride(from: 0.0, to: 6.28, by: 0.3) {
            #expect(RingWobble.offset(theta: theta, t: 12.3, vibe: .vibing) == 0)
        }
    }

    @Test func fewNodesThatStayInsideTheirSize() {
        #expect(RingWobble.nodes(.mid).count == 3)
        #expect(RingWobble.nodes(.cooked).count == 4)
        for vibe in [Vibe.mid, .cooked] {
            let limit = RingWobble.nodes(vibe).size
            for theta in stride(from: 0.0, to: 6.28, by: 0.05) {
                #expect(abs(RingWobble.offset(theta: theta, t: 7.7, vibe: vibe)) <= limit + 1e-9)
            }
        }
    }

    @Test func cookedMovesFasterThanMid() {
        #expect(RingWobble.nodes(.cooked).speed > RingWobble.nodes(.mid).speed)
    }

    @Test func partialArcEndsWhereTheFillDoes() {
        let path = RingWobble.path(center: .init(x: 8, y: 8), radius: 7, fraction: 1.0 / 3, t: 0, vibe: .cooked)
        #expect(!path.isEmpty)
        // A third of the turn from 12 o'clock ends lower right, never past 6 o'clock on the left.
        #expect(path.boundingRect.minX >= 8 - 1)
    }
}

@Suite struct RingWobblePeriodTests {
    @Test func periodRepeatsThePattern() {
        for vibe in [Vibe.mid, .cooked] {
            let p = RingWobble.period(vibe)
            #expect(p > 0)
            for theta in stride(from: 0.0, to: 6.28, by: 0.4) {
                #expect(abs(RingWobble.offset(theta: theta, t: 1.3, vibe: vibe) - RingWobble.offset(theta: theta, t: 1.3 + p, vibe: vibe)) < 1e-9)
            }
        }
        #expect(RingWobble.period(.vibing) == 0)
    }
}
