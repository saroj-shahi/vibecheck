import SwiftUI

/// Every enabled module's compact label, side by side in one status item.
struct CombinedLabel: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: settings.menuBarSpacing.between) {
            ForEach(settings.orderedModules) { MenuBarLabel(module: $0, padded: false) }
        }
        .padding(.horizontal, settings.menuBarSpacing.padding)
    }
}
