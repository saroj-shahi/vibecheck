import AppKit
import Foundation
import SwiftUI
import Testing
@testable import VibeCheck

@MainActor
struct NetworkLabelStyleTests {
    @Test func iconRatesArrowsIsNetworkOnly() {
        #expect(Module.network.labelStyles.contains(.iconValueArrows))
        for module in Module.allCases where module != .network {
            #expect(!module.labelStyles.contains(.iconValueArrows))
        }
    }

    @Test func savedStyleSurvivesAndOtherModulesFallBack() {
        let name = "vibecheck.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        d.set(["network": "iconValueArrows", "cpu": "iconValueArrows"], forKey: "labelStyles")
        let s = AppSettings(defaults: d)
        #expect(s.labelStyle(.network) == .iconValueArrows)
        #expect(s.labelStyle(.cpu) == .standard)
    }

    /// The new style shows the globe and the arrows, so it is wider than either style alone.
    @Test func iconRatesArrowsIsWiderThanEachPart() {
        let name = "vibecheck.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: d)
        let stats = SystemStats()
        func width(_ style: VibeCheck.LabelStyle) -> CGFloat {
            settings.setLabelStyle(style, for: .network)
            return NSHostingView(rootView: MenuBarLabel(module: .network).environment(stats).environment(settings))
                .fittingSize.width
        }
        let both = width(.iconValueArrows)
        #expect(both > width(.standard))
        #expect(both > width(.iconAndValue))
    }
}
