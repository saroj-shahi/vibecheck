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
}
