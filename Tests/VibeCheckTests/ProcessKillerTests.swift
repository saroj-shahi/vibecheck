import Foundation
import Testing
@testable import VibeCheck

@MainActor
struct ProcessKillerTests {
    private func reason(pid: Int32 = 500, name: String = "node", owner: uid_t? = 501) -> String? {
        ProcessKiller.protectionReason(pid: pid, name: name, ownerUID: owner, currentUID: 501, ownPID: 42)
    }

    @Test func protectsMacOSVibeCheckAndOtherUsers() {
        #expect(reason() == nil)
        #expect(reason(pid: 1, name: "launchd") != nil)
        #expect(reason(pid: 0) != nil)
        for name in ["kernel_task", "WindowServer", "loginwindow"] { #expect(reason(name: name) != nil) }
        #expect(reason(pid: 42) == "That's VibeCheck")
        #expect(reason(owner: 0) == "Owned by another user")
        #expect(reason(owner: nil) == "Already gone")
    }

    @Test func realLookups() {
        let me = ProcessInfo.processInfo.processIdentifier
        #expect(ProcessKiller.ownerUID(of: me) == getuid())
        #expect(ProcessKiller.name(of: me) != nil)
        #expect(ProcessKiller.protectionReason(pid: me) == "That's VibeCheck")
        #expect(ProcessKiller.protectionReason(pid: 1) == "Part of macOS")
    }

    /// Quits a throwaway child process (never anything else).
    @Test func quitsAPlainProcess() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["60"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        #expect(ProcessKiller.protectionReason(pid: child.processIdentifier) == nil)
        let target = try #require(ProcessKiller.identity(of: child.processIdentifier))
        // Same pid, different start time (what a reused pid looks like): refused.
        let stale = ProcessKiller.Identity(pid: target.pid, started: target.started - 1)
        #expect(ProcessKiller.quit(stale, mode: .quit) == .failed("Already gone"))
        #expect(child.isRunning)
        #expect(ProcessKiller.quit(target, mode: .quit) == .sent)
        for _ in 0..<40 where child.isRunning { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!child.isRunning)
        #expect(child.terminationReason == .uncaughtSignal)
    }

    @Test func descendantsAreDeepestFirstAndSafe() {
        let tree: [Int32: [Int32]] = [10: [11, 12], 11: [13], 13: [14], 12: [], 14: [10, 1]]  // cycle + launchd
        let order = ProcessKiller.descendants(of: 10) { tree[$0] ?? [] }
        #expect(Set(order) == [11, 12, 13, 14])
        #expect(order.firstIndex(of: 14)! < order.firstIndex(of: 13)!)
        #expect(order.firstIndex(of: 13)! < order.firstIndex(of: 11)!)
        #expect(ProcessKiller.descendants(of: 99) { _ in [] }.isEmpty)
        // The cap stops a runaway walk.
        #expect(ProcessKiller.descendants(of: 2, children: { [$0 + 1] }, limit: 50).count <= 50)
    }

    /// Quits a throwaway shell and its two `sleep` children (never anything else).
    @Test func quitsAProcessTree() async throws {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "/bin/sleep 60 & /bin/sleep 60 & wait"]
        try shell.run()
        defer { if shell.isRunning { shell.terminate() } }
        var kids: [Int32] = []
        for _ in 0..<40 where kids.count < 2 {
            try await Task.sleep(for: .milliseconds(50))
            kids = ProcessKiller.children(of: shell.processIdentifier)
        }
        #expect(kids.count == 2)
        #expect(ProcessKiller.offersSubprocesses(pid: shell.processIdentifier))
        let target = try #require(ProcessKiller.identity(of: shell.processIdentifier))
        #expect(ProcessKiller.quit(target, mode: .quit, subprocesses: true) == .sent)
        for _ in 0..<40 where shell.isRunning || kids.contains(where: { kill($0, 0) == 0 }) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!shell.isRunning)
        for kid in kids { #expect(kill(kid, 0) != 0, "sleep \(kid) still running") }
        defer { for kid in kids { kill(kid, SIGKILL) } }
    }
}
