import AppKit
import SwiftUI
import Testing
@testable import VibeCheck

@MainActor
struct MenuBarLayoutTests {
    private func width(_ view: some View, stats: SystemStats, settings: AppSettings) -> CGFloat {
        NSHostingView(rootView: view.environment(stats).environment(settings)
            ).fittingSize.width
    }

    @Test func tighterSpacingNarrowsEveryItem() {
        let stats = SystemStats()
        let settings = AppSettings.shared
        let original = settings.menuBarSpacing
        defer { settings.menuBarSpacing = original }

        var report: [String] = []
        for module in Module.allCases {
            var widths: [CGFloat] = []
            for spacing in MenuBarSpacing.allCases {
                settings.menuBarSpacing = spacing
                widths.append(width(MenuBarLabel(module: module), stats: stats, settings: settings))
            }
            report.append("\(module.rawValue): \(widths.map { Int($0) })")
            #expect(widths.allSatisfy { $0 > 20 && $0 < 200 }, "\(module) widths \(widths)")
            #expect(widths[0] > widths[1] && widths[1] > widths[2], "\(module) widths \(widths)")
        }
        print("menu bar widths normal/compact/tight →", report.joined(separator: ", "))
    }

    @Test func combinedItemShrinksWithSpacing() {
        let stats = SystemStats()
        let settings = AppSettings.shared
        let original = settings.menuBarSpacing
        defer { settings.menuBarSpacing = original }
        let widths = MenuBarSpacing.allCases.map { spacing -> CGFloat in
            settings.menuBarSpacing = spacing
            return width(CombinedLabel(), stats: stats, settings: settings)
        }
        print("combined widths normal/compact/tight →", widths.map { Int($0) })
        #expect(widths[0] > widths[1] && widths[1] > widths[2])
    }
}
