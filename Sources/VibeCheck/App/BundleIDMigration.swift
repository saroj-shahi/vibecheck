import Foundation

/// VibeCheck 1.5 and earlier used the bundle ID `local.vibecheck.app`, so their settings live in that defaults
/// domain. On the first launch with the new ID, copy them over so an update keeps the user's setup.
/// The old domain is left in place, so going back to an older version still works.
enum BundleIDMigration {
    static let legacyDomain = "local.vibecheck.app"
    /// Set once the copy has been tried, so it runs only once (even when there was nothing to copy).
    static let doneKey = "migratedFromLegacyBundleID"

    /// Returns true if it copied any settings.
    /// - Parameters:
    ///   - defaults: the app's own defaults (the new domain).
    ///   - legacy: reads the old domain; a parameter so tests can use throwaway suites.
    @discardableResult
    static func run(defaults: UserDefaults = .standard,
                    legacy: () -> [String: Any]? = { UserDefaults.standard.persistentDomain(forName: legacyDomain) }) -> Bool {
        guard !defaults.bool(forKey: doneKey) else { return false }
        defer { defaults.set(true, forKey: doneKey) }
        // A user who already has settings under the new ID (e.g. a dev build) keeps them.
        guard defaults.object(forKey: "enabledModules") == nil,
              let old = legacy(), !old.isEmpty else { return false }
        for (key, value) in old { defaults.set(value, forKey: key) }
        return true
    }
}
