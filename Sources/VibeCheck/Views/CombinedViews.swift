import SwiftUI

/// Every enabled module's compact label, side by side in one status item.
struct CombinedLabel: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SystemStats.self) private var stats

    var body: some View {
        HStack(spacing: settings.menuBarSpacing.between) {
            if settings.showVibeRing { VibeRing(vibe: stats.vibe.vibe).frame(height: 22) }
            ForEach(settings.orderedModules) { MenuBarLabel(module: $0, padded: false) }
        }
        .padding(.horizontal, settings.menuBarSpacing.padding)
    }
}
