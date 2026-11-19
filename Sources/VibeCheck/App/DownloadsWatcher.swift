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

/// Tells whether a dropped file or folder is still changing, for the "keep awake while it's written" drop on
/// the ring. Same idea as `DownloadsWatcher`: a scan off the main thread at most every 5 s, and the item counts
/// as busy until nothing under it changed for `DownloadsWatcher.recentWindow`.
@MainActor
final class PathActivity {
    static let shared = PathActivity()

    private var newest: [String: Date] = [:]
    private var scanStarted: [String: Date] = [:]
    private var lastScan: [String: Date] = [:]

    /// Newest modification date seen by the last finished scan.
    func lastChange(_ path: String) -> Date? { newest[path] }

    func refreshIfDue(path: String, now: Date = Date()) {
        if let started = scanStarted[path] {
            guard now.timeIntervalSince(started) > 30 else { return }   // stuck on a stalled volume: try again
        }
        guard lastScan[path].map({ now.timeIntervalSince($0) >= 5 }) ?? true else { return }
        scanStarted[path] = now
        lastScan[path] = now
        Task.detached(priority: .utility) {
            let date = Self.newestModification(URL(fileURLWithPath: path))
            await PathActivity.shared.finish(path: path, date: date)
        }
    }

    private func finish(path: String, date: Date?) {
        scanStarted[path] = nil
        // A vanished path keeps its last known date, so it goes quiet by itself.
        if let date { newest[path] = max(date, newest[path] ?? .distantPast) }
        KeepAwake.shared.check()
    }

    /// Forget a path once its session is over.
    func forget(_ path: String) {
        newest[path] = nil
        scanStarted[path] = nil
        lastScan[path] = nil
    }

    /// Quiet when neither the item's own changes nor the drop itself happened within the recent window.
    nonisolated static func isQuiet(lastChange: Date?, started: Date, now: Date) -> Bool {
        let latest = max(lastChange ?? .distantPast, started)
        return now.timeIntervalSince(latest) >= DownloadsWatcher.recentWindow
    }

    /// Newest modification date of the item and (for a folder) everything inside it, capped so a huge tree
    /// can't keep the scan busy.
    nonisolated static func newestModification(_ url: URL, limit: Int = 5000) -> Date? {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        var newest = (try? url.resourceValues(forKeys: keys))?.contentModificationDate
        guard let walker = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return newest }
        var seen = 0
        for case let child as URL in walker {
            seen += 1
            if seen > limit { break }
            if let date = try? child.resourceValues(forKeys: keys).contentModificationDate,
               date > (newest ?? .distantPast) { newest = date }
        }
        return newest
    }
}
