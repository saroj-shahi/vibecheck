import AppKit
import UniformTypeIdentifiers

/// Export / import / reset of VibeCheck's own preferences (nothing else in the defaults domain is touched).
enum SettingsBackup {
    static let keys = [
        "enabledModules", "knownModules", "refreshInterval", "menuBarStyle", "menuBarSpacing", "labelStyles",
        "colorfulMenuBar", "showVibeRing", "moduleOrder", "hotkeysEnabled", "hotkeyModifier", "alertRules", "clockFormat", "clockShowSeconds",
        "worldClocks", "weatherLocation", "temperatureUnit", "chartRange", "groupProcessesByApp",
    ]
    static let formatKey = "VibeCheckSettingsVersion"

    enum BackupError: LocalizedError {
        case notASettingsFile
        var errorDescription: String? { "That file isn't a VibeCheck settings export." }
    }

    static func exportData(from defaults: UserDefaults = .standard) throws -> Data {
        var values: [String: Any] = [formatKey: 1]
        for key in keys { if let value = defaults.object(forKey: key) { values[key] = value } }
        return try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    }

    /// Applies known keys from an export; unknown keys are ignored. Returns how many settings were applied.
    @discardableResult
    static func importData(_ data: Data, into defaults: UserDefaults = .standard) throws -> Int {
        guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              values[formatKey] != nil else { throw BackupError.notASettingsFile }
        let known = keys.filter { values[$0] != nil }
        for key in known { defaults.set(values[key], forKey: key) }
        return known.count
    }

    static func reset(_ defaults: UserDefaults = .standard) {
        keys.forEach { defaults.removeObject(forKey: $0) }
    }

    // MARK: UI

    @MainActor
    static func runExport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "VibeCheck Settings.plist"
        panel.allowedContentTypes = [.propertyList]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try exportData().write(to: url, options: .atomic)
        } catch {
            showError(error)
        }
    }

    @MainActor
    static func runImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard confirm("Import settings from “\(url.lastPathComponent)”?",
                      detail: "Your current VibeCheck settings will be replaced and VibeCheck will restart.",
                      action: "Import") else { return }
        do {
            try importData(Data(contentsOf: url))
            relaunch()
        } catch {
            showError(error)
        }
    }

    @MainActor
    static func runReset() {
        guard confirm("Reset all VibeCheck settings?",
                      detail: "Menu bar items, alerts, clocks and weather go back to their defaults and VibeCheck restarts. History graphs are kept.",
                      action: "Reset") else { return }
        reset()
        relaunch()
    }

    @MainActor
    private static func confirm(_ message: String, detail: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private static func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        NSApp.activate()
        alert.runModal()
    }

    /// Starts a fresh copy once this one has quit, so every setting is re-read from scratch.
    @MainActor
    private static func relaunch() {
        UserDefaults.standard.synchronize()
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
