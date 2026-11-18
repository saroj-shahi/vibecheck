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
        if pid <= 1 || protectedNames.contains(name) { return "Part of macOS" }
        if pid == ownPID { return "That's VibeCheck" }
        guard let ownerUID else { return "Already gone" }
        if ownerUID != currentUID { return "Owned by another user" }
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

    static func identity(of pid: Int32) -> Identity? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Identity(pid: pid, started: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
    }

    @discardableResult
    static func quit(_ target: Identity, mode: Mode) -> Outcome {
        guard identity(of: target.pid) == target else { return .failed("Already gone") }
        let pid = target.pid
        if let reason = protectionReason(pid: pid) { return .failed(reason) }
        let name = name(of: pid) ?? "It"
        if let app = NSRunningApplication(processIdentifier: pid) {
            let sent = mode == .quit ? app.terminate() : app.forceTerminate()
            return sent ? .sent : .failed("\(name) didn't accept the request")
        }
        if kill(pid, mode == .quit ? SIGTERM : SIGKILL) == 0 { return .sent }
        return .failed(errno == EPERM ? "Not allowed" : "Already gone")
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
