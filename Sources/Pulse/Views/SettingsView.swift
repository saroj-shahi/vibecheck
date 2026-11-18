import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Menu bar items") {
                ForEach(Module.allCases) { module in
                    Toggle(isOn: Binding(
                        get: { settings.isEnabled(module) },
                        set: { settings.setEnabled(module, $0) }
                    )) {
                        Label(module.title, systemImage: module.symbol)
                    }
                    .disabled(settings.isEnabled(module) && settings.enabledModules.count == 1)
                }
            }
            Section("General") {
                Picker("Update every", selection: $settings.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
            Section {
                Text("Pulse 1.0 · Click any menu bar item for details.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}
