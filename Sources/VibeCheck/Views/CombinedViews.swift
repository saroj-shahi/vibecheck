import SwiftUI

/// Every enabled module's compact label, side by side in one status item.
struct CombinedLabel: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: StatusItemController.combinedSpacing) {
            ForEach(settings.orderedModules) { MenuBarLabel(module: $0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The combined item's panel: an icon tab bar on top, the selected module's panel below.
struct CombinedPanel: View {
    @Environment(AppSettings.self) private var settings
    @Environment(CombinedSelection.self) private var selection

    var body: some View {
        let modules = settings.orderedModules
        let current = modules.contains(selection.module) ? selection.module : (modules.first ?? .cpu)
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(modules) { module in
                    Button {
                        selection.module = module
                    } label: {
                        Image(systemName: module.symbol)
                            .font(.system(size: 13))
                            .foregroundStyle(module == current ? module.accent : .secondary)
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .background {
                                if module == current {
                                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(module.title)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            ModulePanel(module: current)
        }
        .frame(width: 320)
    }
}
