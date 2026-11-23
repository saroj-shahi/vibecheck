import Testing
import Foundation
@testable import VibeCheck

struct DevServersTests {
    let home = "/Users/tester"

    func details(exe: String = "/opt/homebrew/bin/node", cwd: String, uid: uid_t = 501,
                 started: UInt64 = 1000) -> ListenerDetails {
        ListenerDetails(executable: exe, workingDirectory: cwd, uid: uid, startedSeconds: started,
                        startedMicros: started * 1_000_000, footprint: 100)
    }

    func port(_ pid: Int32, _ p: Int, _ d: ListenerDetails?, name: String = "node") -> ListeningPort {
        ListeningPort(pid: pid, name: name, port: p, address: "127.0.0.1", user: "me", details: d)
    }

    @Test func classification() {
        #expect(DevServers.isDevServer(details(cwd: home + "/code/app"), home: home, currentUID: 501))
        #expect(!DevServers.isDevServer(nil, home: home, currentUID: 501))
        #expect(!DevServers.isDevServer(details(cwd: home + "/code/app", uid: 0), home: home, currentUID: 501))
        #expect(!DevServers.isDevServer(details(exe: "/Applications/X.app/Contents/MacOS/x", cwd: home + "/a"), home: home, currentUID: 501))
        #expect(!DevServers.isDevServer(details(exe: "/System/Library/foo", cwd: home + "/a"), home: home, currentUID: 501))
        #expect(!DevServers.isDevServer(details(exe: "/usr/libexec/rapportd", cwd: home + "/a"), home: home, currentUID: 501))
        #expect(!DevServers.isDevServer(details(cwd: home), home: home, currentUID: 501))
        #expect(!DevServers.isDevServer(details(cwd: home + "/"), home: home, currentUID: 501))
        #expect(!DevServers.isDevServer(details(cwd: "/"), home: home, currentUID: 501))
        #expect(!DevServers.isDevServer(details(cwd: "/Users/tester2/a"), home: home, currentUID: 501))
    }

    @Test func projectNameFromTempTree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dev-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let proj = root.appendingPathComponent("code/myapp")
        let deep = proj.appendingPathComponent("packages/web/src")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: proj.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let plain = root.appendingPathComponent("code/scratch")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)

        #expect(DevServers.project(for: deep.path, home: root.path).name == "myapp")
        #expect(DevServers.project(for: deep.path, home: root.path).folder == proj.path)
        #expect(DevServers.project(for: plain.path, home: root.path).name == "scratch")
        // a marker more than 5 levels up is ignored
        let tooDeep = proj.appendingPathComponent("a/b/c/d/e/f")
        #expect(DevServers.project(for: tooDeep.path, home: root.path).name == "f")
    }

    @Test func uptimeFormatting() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(DevServers.uptimeText(started: 1_000_000 - 10, now: now) == "1 min")
        #expect(DevServers.uptimeText(started: 1_000_000 - 600, now: now) == "10 min")
        #expect(DevServers.uptimeText(started: 1_000_000 - 3 * 3600 - 5, now: now) == "3 h")
        #expect(DevServers.uptimeText(started: 1_000_000 - 2 * 86_400, now: now) == "2 d")
        #expect(DevServers.isLongRunning(started: 1_000_000 - 86_400, now: now))
        #expect(!DevServers.isLongRunning(started: 1_000_000 - 86_399, now: now))
    }

    @Test func groupsByProject() {
        let a = details(cwd: home + "/code/a", started: 500)
        let a2 = details(cwd: home + "/code/a/web", started: 800)
        let b = details(cwd: home + "/code/b", started: 100)
        let sys = details(exe: "/usr/libexec/x", cwd: home + "/code/c")
        let ports = [port(1, 3000, a), port(2, 5173, a), port(3, 8000, b, name: "python3"),
                     port(4, 9000, sys), port(5, 22, nil), port(6, 4000, a2)]
        let projects = DevServers.projects(from: ports, home: home, currentUID: 501, exists: { _ in false })
        // no markers: a and a/web are separate folders
        #expect(projects.map(\.name) == ["b", "a", "web"])
        #expect(projects[1].ports.map(\.port) == [3000, 5173])
        #expect(projects[1].pids == [1, 2])
        #expect(projects[1].footprint == 200)
        #expect(projects[0].runtimes == ["python3"])

        let marked = DevServers.projects(from: ports, home: home, currentUID: 501,
                                         exists: { $0 == home + "/code/a/.git" })
        #expect(marked.map(\.name) == ["b", "a"])
        #expect(marked[1].ports.count == 3)
        #expect(marked[1].startedSeconds == 500)
    }
}
