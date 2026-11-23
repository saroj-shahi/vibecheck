import Testing
import CoreGraphics
@testable import VibeCheck

struct MenuBarVisibilityTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func backgroundKind() {
        #expect(DeckBackgroundKind.choose(osMajor: 26, reduceTransparency: false) == .liquidGlass)
        #expect(DeckBackgroundKind.choose(osMajor: 15, reduceTransparency: false) == .blur)
        #expect(DeckBackgroundKind.choose(osMajor: 26, reduceTransparency: true) == .opaque)
        #expect(DeckBackgroundKind.choose(osMajor: 14, reduceTransparency: true) == .opaque)
    }

    @Test func onMenuBar() {
        #expect(MenuBarVisibility.isOnMenuBar(frame: CGRect(x: 1000, y: 958, width: 60, height: 24), screenFrames: [screen]))
        #expect(!MenuBarVisibility.isOnMenuBar(frame: CGRect(x: -200, y: 958, width: 60, height: 24), screenFrames: [screen]))
        #expect(!MenuBarVisibility.isOnMenuBar(frame: CGRect(x: 1000, y: 500, width: 60, height: 24), screenFrames: [screen]))
    }

    @Test func verdicts() {
        let good = MenuBarVisibility.Probe(hasWindow: true, isVisible: true, frame: CGRect(x: 1000, y: 958, width: 60, height: 24))
        let noWindow = MenuBarVisibility.Probe(hasWindow: false, isVisible: false, frame: .zero)
        #expect(MenuBarVisibility.verdict(probes: [(good, false)], screenFrames: [screen]) == .visible)
        #expect(MenuBarVisibility.verdict(probes: [(noWindow, false), (good, false)], screenFrames: [screen]) == .visible)
        #expect(MenuBarVisibility.verdict(probes: [(noWindow, false)], screenFrames: [screen]) == .hiddenByMacOS)
        #expect(MenuBarVisibility.verdict(probes: [(good, true)], screenFrames: [screen]) == .hiddenByNotch)
        #expect(MenuBarVisibility.verdict(probes: [], screenFrames: [screen]) == .visible)
    }
}
