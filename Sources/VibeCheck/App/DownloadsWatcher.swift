import Foundation

/// Tells whether files are arriving in a folder (by default ~/Downloads), for the "while downloading"
/// keep-awake trigger. Looks at the folder's top level only, off the main thread, at most every 5 s.
///
/// A download counts as active when a browser's in-progress file is still growing (Chrome `.crdownload`,
/// Safari `.download`, Firefox `.part`, …), or when any file changed in the last few seconds (curl, AirDrop,
/// a copy). Stale in-progress files left by a crash stop counting once they haven't changed for a while.
@MainActor
final class DownloadsWatcher {
    static let shared = DownloadsWatcher()

    /// Last answer from the background scan.
    private(set) var isActive = false
    private var lastScan: Date?
    /// When the running scan started; nil when none is running.
    private var scanStarted: Date?
    /// Bumped by `reset()`, so a scan that was already running when the folder or setting changed is ignored.
    private var generation = 0

    struct Entry: Equatable, Sendable {
        let name: String
        let modified: Date
    }

    /// Extensions browsers use while a download is in progress.
    nonisolated static let inProgressExtensions: Set<String> = ["crdownload", "download", "part", "partial",
                                                                "opdownload", "filepart", "aria2"]
    /// Any file this recent means something is still writing.
    nonisolated static let recentWindow: TimeInterval = 10
    /// In-progress files that haven't changed for this long are treated as stalled or abandoned.
    nonisolated static let stalledAfter: TimeInterval = 120

    /// Pure, for tests.
    nonisolated static func isActive(_ entries: [Entry], now: Date) -> Bool {
        entries.contains { entry in
            guard !entry.name.hasPrefix(".") || inProgress(entry.name) else { return false }
            let age = now.timeIntervalSince(entry.modified)
            return age < recentWindow || (inProgress(entry.name) && age < stalledAfter)
        }
    }

    nonisolated static func inProgress(_ name: String) -> Bool {
        inProgressExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    nonisolated static var defaultFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    /// Starts a background scan if the last one is old enough; `isActive` updates when it finishes.
    func refreshIfDue(folder: URL, now: Date = Date()) {
        if let started = scanStarted {
            // A scan stuck on a stalled network volume must not keep the Mac awake: give up on it.
            guard now.timeIntervalSince(started) > 30 else { return }
            reset()
        }
        guard lastScan.map({ now.timeIntervalSince($0) >= 5 }) ?? true else { return }
        scanStarted = now
        lastScan = now
        let token = generation
        Task.detached(priority: .utility) {
            let active = Self.isActive(Self.scan(folder), now: Date())
            await DownloadsWatcher.shared.finish(active, token: token)
        }
    }

    private func finish(_ active: Bool, token: Int) {
        guard token == generation else { return }   // folder, setting or a timed-out scan: stale answer
        scanStarted = nil
        guard isActive != active else { return }
        isActive = active
        KeepAwake.shared.check()
    }

    /// Forget the last answer and any running scan (trigger switched off, folder changed, scan timed out).
    func reset() {
        generation += 1
        isActive = false
        lastScan = nil
        scanStarted = nil
    }

    /// Top-level entries with their modification time. A Safari `.download` bundle's own date doesn't change
    /// while the file inside grows, so its newest child's date is used instead.
    nonisolated static func scan(_ folder: URL) -> [Entry] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return [] }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  var modified = values.contentModificationDate else { return nil }
            if values.isDirectory == true, inProgress(url.lastPathComponent),
               let inside = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys) {
                for child in inside {
                    if let date = try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                       date > modified { modified = date }
                }
            }
            return Entry(name: url.lastPathComponent, modified: modified)
        }
    }
}
