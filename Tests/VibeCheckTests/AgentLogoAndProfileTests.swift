import CoreGraphics
import Foundation
import Testing
@testable import VibeCheck

struct AgentLogoTests {
    @Test func everyLogoFillsItsBox() {
        for kind in AgentKind.allCases {
            let box = kind.logoPath.boundingBoxOfPath
            #expect(!box.isEmpty, "\(kind) parsed to nothing")
            #expect(box.minX >= -0.1 && box.minY >= -0.1 && box.maxX <= 24.1 && box.maxY <= 24.1, "\(kind): \(box)")
            #expect(max(box.width, box.height) > 14, "\(kind) is too small: \(box)")
        }
    }

    @Test func parsesPackedNumbersRelativeCommandsAndArcs() {
        // "-.5.25" is two numbers; relative lines; a half-circle arc from (0,10) to (20,10).
        let lines = SVGPath.parse("M10 10l-.5.25h2v-1z").boundingBoxOfPath
        #expect(abs(lines.minX - 9.5) < 0.001 && abs(lines.maxX - 11.5) < 0.001)
        let arc = SVGPath.parse("M0 10A10 10 0 0 1 20 10").boundingBoxOfPath
        _ = SVGPath.parse("M0 0h1z5 5")   // a number after Z must not loop forever
        #expect(abs(arc.width - 20) < 0.01 && abs(arc.height - 10) < 0.01 && arc.minY < 0.01)
    }
}

struct AgentMenuBarChoiceTests {
    private let now = Date()
    private func tokens(_ n: Int) -> TokenCounts { TokenCounts(input: n) }

    @Test func logoFollowsTheNumbersSource() {
        var sample = AgentUsageSample(scanned: true)
        let limit = RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: now.addingTimeInterval(3600))
        sample.agents = [AgentSummary(agent: .claude, today: tokens(5), week: tokens(50)),
                         AgentSummary(agent: .codex, today: tokens(20), week: tokens(30), limits: [limit])]
        var o = ItemOptions()
        #expect(sample.menuBarAgent(o) == .codex)          // busiest today
        o.agentValue = .tokensWeek
        #expect(sample.menuBarAgent(o) == .claude)         // busiest this week
        o.agentValue = .limitsLeft
        #expect(sample.menuBarAgent(o) == .codex)          // the one with limits
        o.agents = [.claude]
        o.agentValue = .tokensToday
        #expect(sample.menuBarAgent(o) == .claude)
        o.agents = [.opencode]
        #expect(sample.menuBarAgent(o) == .opencode)       // chosen but not found yet
        #expect(AgentUsageSample().menuBarAgent(ItemOptions()) == .claude)
    }

    @Test func switchingAgentsKeepsAllAsEmptyAndOneOn() {
        var o = ItemOptions()
        o.setAgent(.codex, shown: false)
        #expect(o.agents == [.claude, .copilot, .opencode])
        o.setAgent(.codex, shown: true)
        #expect(o.agents.isEmpty)
        o.agents = [.claude]
        o.setAgent(.claude, shown: false)
        #expect(o.agents == [.claude])
    }
}

struct ClaudeProfileTests {
    private func tempHome() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vc-profiles-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ email: String, to url: URL) throws {
        try Data(#"{"oauthAccount":{"emailAddress":"\#(email)","displayName":"X"}}"#.utf8).write(to: url)
    }

    @Test func findsSecondAccountFoldersAndEmails() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let fm = FileManager.default
        try fm.createDirectory(at: home.appending(path: ".claude/projects"), withIntermediateDirectories: true)
        try write("me@home.test", to: home.appending(path: ".claude.json"))
        try fm.createDirectory(at: home.appending(path: ".claude-work/projects"), withIntermediateDirectories: true)
        try write("me@work.test", to: home.appending(path: ".claude-work/.claude.json"))
        try fm.createDirectory(at: home.appending(path: ".claude-empty"), withIntermediateDirectories: true)   // not a profile
        let custom = home.appending(path: "profiles/alt")
        try fm.createDirectory(at: custom, withIntermediateDirectories: true)

        let profiles = ClaudeProfile.discover(home: home, extra: [custom.path, custom.path, home.appending(path: ".claude").path,
                                                                  home.appending(path: "missing").path])
        #expect(profiles.map(\.label) == ["Default account · me@home.test", "claude-work · me@work.test", "alt"])
        #expect(profiles[0].isDefault)
        let work = profiles[1]
        #expect(work.projectRoots(home: home, environment: [:]).map(\.path) == [home.appending(path: ".claude-work/projects").standardizedFileURL.path])
        #expect(work.configFile(home: home, environment: [:]).lastPathComponent == ".claude.json")
        #expect(work.configDirectoryForCLI == home.appending(path: ".claude-work").standardizedFileURL.path)
        #expect(profiles[0].configDirectoryForCLI == nil)
        #expect(profiles[0].projectRoots(home: home, environment: [:]).first == home.appending(path: ".claude/projects"))
    }

    @Test func scannerReadsOnlyTheChosenAccount() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let work = ClaudeProfile(directory: home.appending(path: ".claude-work"))
        let project = home.appending(path: ".claude-work/projects/p")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))
        let line = #"{"type":"assistant","timestamp":"\#(stamp)","requestId":"r1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":7,"output_tokens":3}}}"#
        try Data((line + "\n").utf8).write(to: project.appending(path: "s.jsonl"))
        try write("me@work.test", to: home.appending(path: ".claude-work/.claude.json"))

        let scanner = AgentUsageScanner(claudeRoots: work.projectRoots(home: home, environment: [:]), codexRoots: [], copilotRoots: [],
                                        opencodeDB: home.appending(path: "none.db"),
                                        claudeConfig: work.configFile(home: home, environment: [:]))
        let claude = try #require(scanner.scan(now: now, fullWalk: true).agents.first { $0.agent == .claude })
        #expect(claude.today.total == 10)
        #expect(AgentNames.claudeEmail(try Data(contentsOf: home.appending(path: ".claude-work/.claude.json"))) == "me@work.test")
    }
}

@Test func switchedOffAgentsAreLeftOutOfTheSample() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "vc-shown-\(UUID().uuidString)")
    let project = dir.appending(path: "p")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let now = Date()
    let stamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))
    let line = #"{"type":"assistant","timestamp":"\#(stamp)","requestId":"r1","message":{"id":"m1","model":"claude-sonnet-4","usage":{"input_tokens":100,"output_tokens":50}}}"#
    try Data((line + "\n").utf8).write(to: project.appending(path: "s.jsonl"))
    let empty = dir.appending(path: "none")
    func scanner() -> AgentUsageScanner {
        AgentUsageScanner(claudeRoots: [dir], codexRoots: [empty], copilotRoots: [empty],
                          opencodeDB: empty.appending(path: "x.db"), claudeConfig: empty.appending(path: "c.json"))
    }
    let all = scanner().scan(now: now, fullWalk: true)
    #expect(all.agents.map(\.agent) == [.claude])
    #expect(all.today.total == 150)
    let hidden = scanner().scan(now: now, fullWalk: true, shown: [.codex])
    #expect(hidden.agents.isEmpty)
    #expect(hidden.today.total == 0)
    #expect(hidden.hourly.reduce(0, +) == 0)
    #expect(hidden.found == [.claude])
}
