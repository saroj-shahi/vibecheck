import AppKit
import SwiftUI

/// Debug-only launch mode, kept out of `AppDelegate.swift`. Compiled into release builds on purpose:
/// `build/VibeCheck.app/Contents/MacOS/VibeCheck --deck-demo` is how deck and Settings frames are checked.
extension AppDelegate {
    /// `--deck-demo`: opens the deck, unfolds CPU, folds back, and logs the window frame at each step.
    func runDeckDemo() {
        func log(_ step: String) {
            let window = NSApp.windows.first { $0 is DeckPanel }
            NSLog("%@", "VibeCheck deck-demo \(step): visible=\(window?.isVisible ?? false) frame=\(NSStringFromRect(window?.frame ?? .zero)) route=\(deck.route)")
        }
        let steps: [(Double, String, () -> Void)] = [
            (1.0, "launch", {
                for item in [self.combinedItem, self.vibeItem].compactMap({ $0 }) + Array(self.items.values) {
                    guard let button = item.button, let window = button.window else { continue }
                    let inScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
                    NSLog("%@", "VibeCheck deck-demo item \(item.kind) shown=\(item.fit.visibleCount.map(String.init) ?? "all"): window=\(NSStringFromRect(window.frame)) buttonOnScreen=\(NSStringFromRect(inScreen)) screen=\(NSStringFromRect(window.screen?.frame ?? .zero)) visible=\(NSStringFromRect(window.screen?.visibleFrame ?? .zero))")
                }
                // What the combined item would show beside the notch, using the real label widths.
                let spacing = self.settings.menuBar.spacing
                let widths = self.settings.orderedModules.map { module in
                    NSHostingView(rootView: MenuBarLabel(module: module, padded: false)
                        .environment(self.stats).environment(self.settings)).fittingSize.width
                }
                let chip = NSHostingView(rootView: HiddenCountChip(count: 8)).fittingSize.width
                for room in [189.0, 300.0] {
                    let fitted = NotchFit.visibleCount(itemWidths: widths, fixed: 16 + spacing.padding * 2, gap: spacing.between,
                                                       chipWidth: chip, available: room)
                    let count = NotchFit.capped(fitted: fitted, total: widths.count, cap: self.settings.menuBar.notchMaxStats)
                    let names = count.map { self.settings.orderedModules.prefix($0).map(\.title).joined(separator: ", ") } ?? "all"
                    NSLog("%@", "VibeCheck deck-demo notch-fit room=\(Int(room)): \(names) + \(count.map { "+\(self.settings.orderedModules.count - $0)" } ?? "none")")
                }
                for screen in NSScreen.screens {
                    NSLog("%@", "VibeCheck deck-demo screen: frame=\(NSStringFromRect(screen.frame)) visible=\(NSStringFromRect(screen.visibleFrame))")
                }
                guard let button = (self.combinedItem ?? self.items[.network] ?? self.items.values.first)?.button else { return }
                self.deck.ignoresOutsideClicks = true
                self.deck.open(from: button, route: .home)
            }),
            (1.6, "home", { self.deck.model.go(.module(.cpu)) }),
            (2.4, "cpu", { self.deck.model.go(.home) }),
            (3.2, "home-again", { self.deck.close() }),
            (3.8, "closed", { self.deck.ignoresOutsideClicks = false; self.showSettings() }),
            (4.8, "settings", {
                let window = NSApp.windows.first { $0.title == String(localized: "VibeCheck Settings") }
                NSLog("%@", "VibeCheck deck-demo settings-window: visible=\(window?.isVisible ?? false) frame=\(NSStringFromRect(window?.frame ?? .zero)) vibe=\(self.stats.vibe.vibe.title) verdict=\(self.stats.vibe.verdict)")
                window?.close()
            }),
        ]
        for (time, name, action) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) { log(name); action() }
        }
    }
}
