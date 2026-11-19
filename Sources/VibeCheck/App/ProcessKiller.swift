import AppKit
import Darwin

/// Quit and Force Quit for the "Who's responsible" rows. Apps go through `NSRunningApplication` (so they
/// can save and clean up); plain processes get SIGTERM / SIGKILL. Some processes are never offered.
@MainActor
enum ProcessKiller {
    enum Mode { case quit, forceQuit }

    enum Outcome: Equatable {
        case sent
        case failed(String)
    }

    /// Killing these logs the user out, hangs the Mac or panics it.
    nonisolated static let protectedNames: Set<String> = ["kernel_task", "launchd", "WindowServer", "loginwindow"]

    /// Why a process can't be quit from VibeCheck, or nil if it can. Pure, for tests.
    nonisolated static func protectionReason(pid: Int32, name: String, ownerUID: uid_t?,
                                             currentUID: uid_t, ownPID: Int32) -> String? {
        if pid <= 1 || protectedNames.contains(name) { return String(localized: "Part of macOS") }
        if pid == ownPID { return String(localized: "That's VibeCheck") }
        guard let ownerUID else { return String(localized: "Already gone") }
        if ownerUID != currentUID { return String(localized: "Owned by another user") }
        return nil
    }

    static func protectionReason(pid: Int32) -> String? {
        protectionReason(pid: pid, name: processName(of: pid) ?? "", ownerUID: ownerUID(of: pid),
                         currentUID: getuid(), ownPID: ProcessInfo.processInfo.processIdentifier)
    }

    /// A pid plus its start time: pids get reused, so a menu or confirmation built for one process must
    /// never signal a different process that later got the same pid.
    struct Identity: Equatable {
        let pid: Int32
        let started: UInt64   // microseconds since 1970
    }

    static func identity(of pid: Int32) -> Identity? { identityAndParent(of: pid)?.0 }

    /// Identity plus parent pid, read in one call.
    static func identityAndParent(of pid: Int32) -> (Identity, Int32)? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return (Identity(pid: pid, started: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec),
                Int32(info.pbi_ppid))
    }

    /// Quits one process, or with `subprocesses` its whole tree: children first (deepest first), then the
    /// process itself. For CLI tools like `npm run dev`, whose children outlive a quit parent.
    @discardableResult
    static func quit(_ target: Identity, mode: Mode, subprocesses: Bool = false) -> Outcome {
        guard identity(of: target.pid) == target else { return .failed(String(localized: "Already gone")) }
        let pid = target.pid
        if let reason = protectionReason(pid: pid) { return .failed(reason) }
        if subprocesses {
            // Pause the root so a supervisor (nodemon, a shell loop) can't respawn children meanwhile.
            kill(pid, SIGSTOP)
            defer { kill(pid, SIGCONT) }   // a stopped process only acts on SIGTERM once continued
            var parentOf: [Int32: Int32] = [:]
            let order = descendants(of: pid) { parent in
                let kids = children(of: parent)
                for kid in kids { parentOf[kid] = parent }
                return kids
            }
            // Each identity is taken only if the pid is still the child of the parent it was found under,
            // so a pid recycled during the walk is never signalled.
            let tree = order.compactMap { kid -> Identity? in
                guard let (id, parent) = identityAndParent(of: kid), parent == parentOf[kid] else { return nil }
                return id
            }
            var refused = 0
            for child in tree {
                if protectionReason(pid: child.pid) != nil { refused += 1; continue }
                // "Already gone" is fine: a child often exits when its own parent does.
                if case .failed(let text) = quit(child, mode: mode), text != String(localized: "Already gone") { refused += 1 }
            }
            var outcome = quit(target, mode: mode)
            // Parents (npm, shells) often exit as their children die: that's success, not "Already gone".
            if outcome == .failed(String(localized: "Already gone")), identity(of: pid) != target { outcome = .sent }
            if outcome == .sent, refused > 0 {
                return .failed(refused == 1 ? String(localized: "1 subprocess still running") : String(localized: "\(refused) subprocesses still running"))
            }
            return outcome
        }
        let name = name(of: pid) ?? "It"
        if let app = NSRunningApplication(processIdentifier: pid) {
            let sent = mode == .quit ? app.terminate() : app.forceTerminate()
            return sent ? .sent : .failed("\(name) didn't accept the request")
        }
        if kill(pid, mode == .quit ? SIGTERM : SIGKILL) == 0 { return .sent }
        return .failed(errno == EPERM ? String(localized: "Not allowed") : String(localized: "Already gone"))
    }

    /// Direct children of a process (one syscall), up to `max`.
    nonisolated static func children(of pid: Int32, max: Int = 8192) -> [Int32] {
        var buffer = [Int32](repeating: 0, count: max)
        let count = buffer.withUnsafeMutableBytes { proc_listchildpids(pid, $0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [] }
        return buffer.prefix(min(Int(count), buffer.count)).filter { $0 > 0 }
    }

    /// Every descendant of `root`, deepest first (so children go before their parents). Guards against
    /// cycles and caps the walk. Pure apart from `children`, for tests.
    nonisolated static func descendants(of root: Int32, children: (Int32) -> [Int32],
                                        limit: Int = 1024) -> [Int32] {
        var seen: Set<Int32> = [root]
        var order: [Int32] = []
        func visit(_ pid: Int32) {
            for child in children(pid) where child > 1 && !seen.contains(child) && seen.count <= limit {
                seen.insert(child)
                visit(child)
                order.append(child)
            }
        }
        visit(root)
        return order
    }

    /// Whether to offer "and subprocesses": plain processes (apps clean up their own helpers) with children.
    static func offersSubprocesses(pid: Int32) -> Bool {
        !children(of: pid, max: 1).isEmpty && NSRunningApplication(processIdentifier: pid) == nil
    }

    /// What the pid really is right now: the app's name, else the process name. Menu labels use this,
    /// not the row's name (a grouped row can carry a helper's name while its pid is the owner's).
    static func name(of pid: Int32) -> String? {
        NSRunningApplication(processIdentifier: pid)?.localizedName ?? processName(of: pid)
    }

    /// Short process name (what the protected list matches), independent of the app's display name.
    private static func processName(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cBuffer: buffer)
    }

    /// The owning user of a process, or nil if it no longer exists.
    static func ownerUID(of pid: Int32) -> uid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_uid
    }
}
