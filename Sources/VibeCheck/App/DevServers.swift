import Foundation
import Darwin

/// What libproc says about a listening process, read in the same background pass as `lsof`.
struct ListenerDetails: Equatable, Sendable {
    let executable: String
    let workingDirectory: String
    let uid: uid_t
    let startedSeconds: UInt64   // seconds since 1970
    let startedMicros: UInt64    // microseconds since 1970 (matches `ProcessKiller.Identity.started`)
    let footprint: UInt64?       // bytes, nil when unreadable
    /// Project folder and name, resolved on the background queue so the view never touches the disk.
    var projectFolder: String?
    var projectName: String?

    nonisolated static func read(pid: Int32) -> ListenerDetails? {
        var bsd = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize else { return nil }

        var vnode = proc_vnodepathinfo()
        let vSize = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        var cwd = ""
        if proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, vSize) == vSize {
            cwd = withUnsafeBytes(of: &vnode.pvi_cdir.vip_path) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
        }

        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        let exe = n > 0 ? String(cBuffer: pathBuffer) : ""

        var usage = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        let home = NSHomeDirectory()
        let resolved = cwd.hasPrefix(home + "/") ? DevServers.project(for: cwd, home: home) : nil
        return ListenerDetails(executable: exe, workingDirectory: cwd, uid: bsd.pbi_uid,
                               startedSeconds: bsd.pbi_start_tvsec,
                               startedMicros: bsd.pbi_start_tvsec * 1_000_000 + bsd.pbi_start_tvusec,
                               footprint: ok == 0 ? usage.ri_phys_footprint : nil,
                               projectFolder: resolved?.folder, projectName: resolved?.name)
    }
}

/// One project's forgotten local servers, grouped by project folder.
struct DevProject: Identifiable, Equatable, Sendable {
    let folder: String
    let name: String
    let ports: [ListeningPort]
    let runtimes: [String]
    let startedSeconds: UInt64   // the oldest process
    let footprint: UInt64?

    var id: String { folder }
    var pids: [Int32] { Array(Set(ports.map(\.pid))).sorted() }
}

enum DevServers {
    /// A dev server: the current user's, not an app bundle or system binary, working in a project folder
    /// inside home (not home itself). Pure, for tests.
    nonisolated static func isDevServer(_ details: ListenerDetails?, home: String, currentUID: uid_t) -> Bool {
        guard let d = details, d.uid == currentUID, !d.executable.isEmpty else { return false }
        if d.executable.contains(".app/") || d.executable.hasSuffix(".app") { return false }
        if d.executable.hasPrefix("/System/") || d.executable.hasPrefix("/usr/libexec/") { return false }
        let home = trimmed(home)
        let cwd = trimmed(d.workingDirectory)
        return !home.isEmpty && cwd.hasPrefix(home + "/") && cwd != home
    }

    /// The working directory's name, or the nearest parent (up to 5 levels, never above home) holding
    /// `.git` or `package.json`. Returns the folder path and its display name.
    nonisolated static func project(for cwd: String, home: String,
                                    exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) })
        -> (folder: String, name: String) {
        let home = trimmed(home)
        var dir = trimmed(cwd)
        let start = dir
        for _ in 0...5 {
            guard dir.hasPrefix(home + "/"), dir != home else { break }
            if exists(dir + "/.git") || exists(dir + "/package.json") { return (dir, lastComponent(dir)) }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return (start, lastComponent(start))
    }

    /// Groups dev-server listeners by project, oldest first so the most forgotten sits on top.
    nonisolated static func projects(from ports: [ListeningPort], home: String, currentUID: uid_t,
                                     exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) })
        -> [DevProject] {
        var groups: [String: (name: String, ports: [ListeningPort])] = [:]
        for port in ports where isDevServer(port.details, home: home, currentUID: currentUID) {
            guard let d = port.details else { continue }
            let p: (folder: String, name: String)
            if let f = d.projectFolder, let n = d.projectName { p = (f, n) }
            else { p = project(for: d.workingDirectory, home: home, exists: exists) }
            groups[p.folder, default: (p.name, [])].ports.append(port)
        }
        return groups.map { folder, g in
            var seen = Set<Int32>()
            var footprint: UInt64?
            for port in g.ports where seen.insert(port.pid).inserted {
                if let f = port.details?.footprint { footprint = (footprint ?? 0) + f }
            }
            var runtimes: [String] = []
            for port in g.ports where !runtimes.contains(port.name) { runtimes.append(port.name) }
            return DevProject(folder: folder, name: g.name, ports: g.ports.sorted { $0.port < $1.port },
                              runtimes: runtimes,
                              startedSeconds: g.ports.compactMap { $0.details?.startedSeconds }.min() ?? 0,
                              footprint: footprint)
        }.sorted { ($0.startedSeconds, $0.folder) < ($1.startedSeconds, $1.folder) }
    }

    /// "5 min", "3 h", "2 d".
    nonisolated static func uptimeText(started: UInt64, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince1970) - Int(started))
        if seconds < 3600 { return "\(max(1, seconds / 60)) min" }
        if seconds < 86_400 { return "\(seconds / 3600) h" }
        return "\(seconds / 86_400) d"
    }

    nonisolated static func isLongRunning(started: UInt64, now: Date = Date()) -> Bool {
        Int(now.timeIntervalSince1970) - Int(started) >= 86_400
    }

    private nonisolated static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private nonisolated static func lastComponent(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
