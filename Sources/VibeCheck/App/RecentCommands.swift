import Foundation

/// The palette's short most-recently-used list of command ids, newest first.
enum RecentCommands {
    nonisolated static let key = "recentCommands"
    nonisolated static let capacity = 8

    nonisolated static func load(_ defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    /// `id` moved to the front, duplicates dropped, trimmed to `capacity`. Pure, for tests.
    nonisolated static func updated(_ list: [String], with id: String) -> [String] {
        Array(([id] + list.filter { $0 != id }).prefix(capacity))
    }

    nonisolated static func record(_ id: String, defaults: UserDefaults = .standard) {
        defaults.set(updated(load(defaults), with: id), forKey: key)
    }
}
