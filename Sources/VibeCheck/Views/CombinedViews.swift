import SwiftUI

/// Every enabled module's compact label, side by side in one status item.
struct CombinedLabel: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SystemStats.self) private var stats
    /// Set only on the real menu bar item; the Settings preview always shows everything.
    @Environment(CombinedFit.self) private var fit: CombinedFit?

    var body: some View {
        let all = settings.orderedModules
        let shown = fit?.visibleCount.map { Array(all.prefix($0)) } ?? all
        HStack(spacing: settings.menuBarSpacing.between) {
            if settings.showVibeRing { VibeRing(vibe: stats.vibe.vibe).frame(height: 22) }
            if AwakeCup.isShown(settings) { AwakeCup() }
            ForEach(shown) { MenuBarLabel(module: $0, padded: false) }
            if shown.count < all.count {
                HiddenCountChip(count: all.count - shown.count)
            }
        }
        .padding(.horizontal, settings.menuBarSpacing.padding)
    }
}

/// "+3": stats hidden to keep the item clear of the camera notch (they're all in the deck).
struct HiddenCountChip: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.system(size: 9, weight: .bold).monospacedDigit())
            .padding(.horizontal, 4)
            .frame(height: 14)
            .background(Capsule().fill(.primary.opacity(0.14)))
            .frame(height: 22)
            .help("\(count) more in the deck. Click to see everything.")
            .accessibilityLabel("\(count) more stats in the deck")
    }
}

/// Small cup shown in the menu bar while a keep-awake session runs.
struct AwakeCup: View {
    @MainActor static func isShown(_ settings: AppSettings) -> Bool {
        settings.keepAwakeShowInMenuBar && KeepAwake.shared.isActive
    }

    var body: some View {
        Image(systemName: "cup.and.saucer.fill")
            .font(.system(size: 11, weight: .medium))
            .frame(height: 22)
            .help("Keeping your Mac awake")
            .accessibilityLabel("Keeping your Mac awake")
    }
}
