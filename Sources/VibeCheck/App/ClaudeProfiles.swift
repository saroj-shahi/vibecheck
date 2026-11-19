import Foundation
import Observation

/// One Claude Code sign-in on this Mac. People with two accounts run Claude Code with
/// `CLAUDE_CONFIG_DIR=~/.claude-work` (or similar); each such folder has its own `projects/` logs and
/// `.claude.json`. `directory == nil` is the default account (`~/.claude`, `~/.claude.json`).
struct ClaudeProfile: Identifiable, Equatable, Sendable {
    var directory: URL?
    /// Signed-in email from the profile's `.claude.json`; nil when signed out or unreadable.
    var email: String?

    static let defaultID = ""
    var id: String { directory?.standardizedFileURL.path ?? Self.defaultID }
    var isDefault: Bool { directory == nil }

    /// "Default account" or the folder's name (".claude-work" → "claude-work").
    var title: String {
        guard let directory else { return String(localized: "Default account") }
        let name = directory.lastPathComponent
        return name.hasPrefix(".") ? String(name.dropFirst()) : name
    }

    /// "Default account · me@example.com".
    var label: String { email.map { "\(title) · \($0)" } ?? title }

    /// Folders holding the profile's session logs.
    func projectRoots(home: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        if let directory { return [directory.appending(path: "projects")] }
        var roots = [home.appending(path: ".claude/projects"), home.appending(path: ".config/claude/projects")]
        if let dir = environment["CLAUDE_CONFIG_DIR"] { roots.append(URL(fileURLWithPath: dir).appending(path: "projects")) }
        return roots
    }

    /// The profile's `.claude.json` (account name, email, plan).
    func configFile(home: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let directory { return directory.appending(path: ".claude.json") }
        return (environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? home).appending(path: ".claude.json")
    }

    /// `CLAUDE_CONFIG_DIR` for running Claude Code as this account; nil keeps the default.
    var configDirectoryForCLI: String? { directory?.path }

    /// Default first, then `~/.claude-*` / `~/.claude_*` folders that look like Claude Code profiles, then folders
    /// the user added. Paths that don't exist are dropped; duplicates and `~/.claude` itself are skipped.
    static func discover(home: URL, extra: [String], fileManager: FileManager = .default) -> [ClaudeProfile] {
        func readEmail(_ url: URL) -> String? { (try? Data(contentsOf: url)).flatMap(AgentNames.claudeEmail) }
        let defaultProfile = ClaudeProfile(directory: nil)
        var profiles = [ClaudeProfile(directory: nil, email: readEmail(defaultProfile.configFile(home: home)))]
        var seen: Set<String> = [home.appending(path: ".claude").standardizedFileURL.path]

        func add(_ url: URL) {
            let url = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  seen.insert(url.path).inserted else { return }
            profiles.append(ClaudeProfile(directory: url, email: readEmail(url.appending(path: ".claude.json"))))
        }

        let names = ((try? fileManager.contentsOfDirectory(atPath: home.path)) ?? []).sorted()
        for name in names where name.hasPrefix(".claude-") || name.hasPrefix(".claude_") {
            let url = home.appending(path: name)
            if looksLikeProfile(url, fileManager: fileManager) { add(url) }
        }
        for path in extra { add(URL(fileURLWithPath: (path as NSString).expandingTildeInPath)) }
        return profiles
    }

    /// Has Claude Code's `projects/` folder or `.claude.json`. Other folders are never handed to Claude Code
    /// as `CLAUDE_CONFIG_DIR`, or it would write its state into them.
    static func looksLikeProfile(_ url: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: url.appending(path: "projects").path)
            || fileManager.fileExists(atPath: url.appending(path: ".claude.json").path)
    }
}

/// Which Claude Code account the Agents module reads. Per Mac (paths), so it's not in settings exports.
@Observable
@MainActor
final class ClaudeProfiles {
    static let shared = ClaudeProfiles()
    nonisolated static let selectedKey = "claudeProfileDir"
    nonisolated static let extraKey = "claudeProfileExtraDirs"

    private(set) var profiles: [ClaudeProfile] = []

    /// `ClaudeProfile.id` of the chosen account ("" = default).
    var selectedID: String = UserDefaults.standard.string(forKey: ClaudeProfiles.selectedKey) ?? ClaudeProfile.defaultID {
        didSet {
            guard oldValue != selectedID else { return }
            UserDefaults.standard.set(selectedID, forKey: Self.selectedKey)
            AgentUsageStore.shared.claudeProfileChanged()
            ClaudeLiveLimits.shared.profileChanged()
        }
    }

    /// Folders added with "Choose account folder…".
    private(set) var extraPaths: [String] = UserDefaults.standard.stringArray(forKey: ClaudeProfiles.extraKey) ?? []

    init() {
        // Not `refresh()`: resetting the selection here would reach AgentUsageStore while it's being created.
        profiles = ClaudeProfile.discover(home: FileManager.default.homeDirectoryForCurrentUser, extra: extraPaths)
    }

    /// The chosen account, or the default one if its folder is gone.
    var selected: ClaudeProfile {
        profiles.first { $0.id == selectedID } ?? profiles.first ?? ClaudeProfile(directory: nil)
    }

    /// Finds profiles again; a chosen folder that's gone falls back to the default account, visibly.
    func refresh() {
        profiles = ClaudeProfile.discover(home: FileManager.default.homeDirectoryForCurrentUser, extra: extraPaths)
        if !profiles.contains(where: { $0.id == selectedID }) { selectedID = ClaudeProfile.defaultID }
    }

    /// Adds a folder picked by the user and selects it. False when it isn't a Claude Code profile.
    @discardableResult
    func add(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path == FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude").standardizedFileURL.path {
            selectedID = ClaudeProfile.defaultID
            return true
        }
        guard ClaudeProfile.looksLikeProfile(url) else { return false }
        if !extraPaths.contains(path) {
            extraPaths.append(path)
            UserDefaults.standard.set(extraPaths, forKey: Self.extraKey)
        }
        refresh()
        if let profile = profiles.first(where: { $0.id == path }) { selectedID = profile.id }
        return true
    }
}
