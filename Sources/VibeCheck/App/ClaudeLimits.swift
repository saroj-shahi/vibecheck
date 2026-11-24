import Foundation
import Observation

/// Opt-in: asks the user's own Claude Code CLI for Claude's real plan limits (5-hour and weekly) and hands them
/// to the Agents module. Claude Code signs in itself; no Keychain access, no network request from this app,
/// no model request.
@Observable
@MainActor
final class ClaudeLiveLimits {
    static let shared = ClaudeLiveLimits()
    nonisolated static let defaultsKey = "claudeLiveLimits"
    /// Live limits older than this are ignored.
    nonisolated static let staleAfter: TimeInterval = 15 * 60
    nonisolated static let normalInterval: TimeInterval = 5 * 60
    nonisolated static let errorInterval: TimeInterval = 15 * 60

    enum Outcome: Equatable { case none, live, notInstalled, signedOut, noAnswer }

    var isOn: Bool = UserDefaults.standard.bool(forKey: ClaudeLiveLimits.defaultsKey) {
        didSet {
            guard oldValue != isOn else { return }
            UserDefaults.standard.set(isOn, forKey: Self.defaultsKey)
            updateTimer()
            if isOn { lastAttempt = .distantPast; outcome = .none; tick() } else { AgentUsageStore.shared.reapply() }
        }
    }

    private(set) var windows: [RateWindow] = []
    /// Subscription type reported by Claude Code (e.g. "team", "max"); stored for display elsewhere.
    private(set) var plan: String?
    private(set) var fetchedAt: Date?
    private(set) var outcome: Outcome = .none
    @ObservationIgnored private var lastAttempt = Date.distantPast
    @ObservationIgnored private var fetching = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var started = false

    /// Live windows that may be shown right now (empty when off or stale).
    func currentWindows(now: Date = Date()) -> [RateWindow] {
        guard isOn, let fetchedAt, now.timeIntervalSince(fetchedAt) < Self.staleAfter else { return [] }
        return windows.filter { $0.resetsAt > now }
    }

    func start() {
        guard !started else { return }
        started = true
        updateTimer()
        if isOn { tick() }
    }

    private func updateTimer() {
        timer?.invalidate()
        timer = nil
        guard started, isOn else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { ClaudeLiveLimits.shared.tick() }
        }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Fetches when the setting and the Agents module are on and the next fetch is due.
    private func tick(now: Date = Date()) {
        guard isOn, !TickGate.isSuspended, AppSettings.shared.isEnabled(.agents), !fetching else { return }
        let interval = outcome == .live || outcome == .none ? Self.normalInterval : Self.errorInterval
        guard now.timeIntervalSince(lastAttempt) >= interval else { return }
        fetching = true
        lastAttempt = now
        let profile = ClaudeProfiles.shared.selected
        let configDirectory = profile.configDirectoryForCLI
        Task {
            let result = await Task.detached(priority: .utility) { ClaudeLimitsClient.fetch(configDirectory: configDirectory) }.value
            ClaudeLiveLimits.shared.finish(result, profile: profile.id)
        }
    }

    /// The Claude account changed: forget the old account's limits and ask again.
    func profileChanged() {
        windows = []
        plan = nil
        fetchedAt = nil
        outcome = .none
        lastAttempt = .distantPast
        AgentUsageStore.shared.reapply()
        if !fetching { tick() }
    }

    private func finish(_ result: ClaudeLimitsClient.Result, profile: String) {
        fetching = false
        guard isOn else { return }
        guard profile == ClaudeProfiles.shared.selected.id else { tick(); return }
        switch result {
        case .usage(let list, let plan):
            windows = list
            self.plan = plan
            fetchedAt = Date()
            outcome = .live
        case .notInstalled: outcome = .notInstalled
        case .signedOut: outcome = .signedOut
        case .noAnswer: outcome = .noAnswer
        }
        AgentUsageStore.shared.reapply()
    }

    func statusText(now: Date = Date()) -> String {
        switch outcome {
        case .none: return String(localized: "Waiting for the first update")
        case .notInstalled: return String(localized: "Claude Code isn't installed")
        case .signedOut: return String(localized: "Claude Code is signed out")
        case .noAnswer: return String(localized: "Claude Code didn't answer")
        case .live:
            guard let fetchedAt else { return String(localized: "Waiting for the first update") }
            let minutes = max(0, Int(now.timeIntervalSince(fetchedAt) / 60))
            return minutes == 0 ? String(localized: "Live from Claude Code · updated just now") : String(localized: "Live from Claude Code · updated \(String(minutes)) min ago")
        }
    }

    /// Pure merge rule: fresh live limits replace Claude's limits; everything else is left as is.
    nonisolated static func merge(_ sample: AgentUsageSample, live: [RateWindow], fetchedAt: Date?, now: Date) -> AgentUsageSample {
        let live = live.filter { $0.resetsAt > now }   // a window that has reset since the fetch is wrong now
        guard !live.isEmpty, let fetchedAt, now.timeIntervalSince(fetchedAt) < staleAfter,
              let index = sample.agents.firstIndex(where: { $0.agent == .claude }) else { return sample }
        var merged = sample
        merged.agents[index].limits = live
        return merged
    }
}

/// Runs the user's Claude Code CLI to read plan usage. Only called when the setting is on.
enum ClaudeLimitsClient {
    enum Result: Sendable {
        case usage([RateWindow], plan: String?)
        case notInstalled
        case signedOut
        case noAnswer
    }

    /// The `get_usage` answer, reduced to what we show.
    struct Usage: Equatable {
        var windows: [RateWindow]
        var plan: String?
        /// False when Claude Code says limits aren't available (signed out) or sent none.
        var available: Bool
    }

    /// What the line protocol produced for the `usage` request.
    enum Reply: Equatable {
        case payload(Data)
        case failure
    }

    nonisolated static let timeout: TimeInterval = 30
    nonisolated static let arguments = [
        "--print", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
        "--no-session-persistence", "--tools", "", "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
        "--setting-sources", "", "--settings", #"{"disableAllHooks":true}"#,
    ]
    nonisolated static let requests =
        #"{"type":"control_request","request_id":"init","request":{"subtype":"initialize"}}"# + "\n" +
        #"{"type":"control_request","request_id":"usage","request":{"subtype":"get_usage","skip_behaviors":true}}"# + "\n"

    /// First executable Claude Code in the usual install locations.
    nonisolated static func findCLI(home: String = NSHomeDirectory(), fileManager: FileManager = .default) -> URL? {
        let candidates = [home + "/.local/bin/claude", home + "/.claude/local/claude",
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// Blocking; call off the main thread. Hard 30 s limit for the whole exchange.
    /// `configDirectory` runs Claude Code as another account (`CLAUDE_CONFIG_DIR`); nil uses the default.
    nonisolated static func fetch(configDirectory: String? = nil) -> Result {
        guard let cli = findCLI() else { return .notInstalled }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vibecheck-claude-" + UUID().uuidString)
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return .noAnswer }
        defer { try? FileManager.default.removeItem(at: directory) }

        let process = Process()
        process.executableURL = cli
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        if let configDirectory { environment["CLAUDE_CONFIG_DIR"] = configDirectory }
        process.environment = environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let collector = LineCollector()
        output.fileHandleForReading.readabilityHandler = { handle in collector.add(handle.availableData) }
        do { try process.run() } catch { output.fileHandleForReading.readabilityHandler = nil; return .noAnswer }
        // Throwing write: if Claude Code has already exited, this fails instead of raising SIGPIPE.
        guard (try? input.fileHandleForWriting.write(contentsOf: Data(requests.utf8))) != nil else {
            output.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
            return .noAnswer
        }

        let answered = collector.wait(timeout: timeout)
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        guard answered, let reply = collector.reply else { return .noAnswer }
        switch reply {
        case .failure: return .noAnswer
        case .payload(let data):
            let usage = parse(data)
            if !usage.available { return .signedOut }
            return usage.windows.isEmpty ? .noAnswer : .usage(usage.windows, plan: usage.plan)
        }
    }

    /// Line protocol: the first `control_response` for request id "usage" decides; other lines are ignored.
    nonisolated static func reply(fromLines lines: [String]) -> Reply? {
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "control_response",
                  let response = object["response"] as? [String: Any],
                  response["request_id"] as? String == "usage" else { continue }
            guard response["subtype"] as? String == "success",
                  let payload = response["response"] as? [String: Any],
                  let bytes = try? JSONSerialization.data(withJSONObject: payload) else { return .failure }
            return .payload(bytes)
        }
        return nil
    }

    /// Pure parse of the `get_usage` payload.
    nonisolated static func parse(_ data: Data) -> Usage {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Usage(windows: [], plan: nil, available: false)
        }
        let plan = (object["subscription_type"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard object["rate_limits_available"] as? Bool != false,
              let limits = object["rate_limits"] as? [String: Any] else {
            return Usage(windows: [], plan: plan, available: false)
        }
        let keys: [(String, Int, String?)] = [("five_hour", 300, nil), ("seven_day", 10080, nil),
                                              ("seven_day_opus", 10080, String(localized: "Weekly · Opus")),
                                              ("seven_day_sonnet", 10080, String(localized: "Weekly · Sonnet"))]
        let windows = keys.compactMap { key, minutes, name -> RateWindow? in
            guard let window = limits[key] as? [String: Any],
                  let used = (window["utilization"] as? NSNumber)?.doubleValue, used.isFinite,
                  let reset = date(window["resets_at"] as? String) else { return nil }   // no reset time: can't show it
            return RateWindow(usedPercent: min(max(used, 0), 100), windowMinutes: minutes, resetsAt: reset, name: name)
        }
        return Usage(windows: windows, plan: plan, available: true)
    }

    nonisolated static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: string) { return d }
        // Fractional parts longer than milliseconds: drop them and retry.
        if let dot = string.firstIndex(of: "."),
           let end = string[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            return plain.date(from: String(string[..<dot]) + String(string[end...]))
        }
        return nil
    }
}

/// Collects process output on the reader thread and signals once the usage reply (or end of output) arrives.
private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var buffer = Data()
    private var lines: [String] = []
    private var finished = false
    private var result: ClaudeLimitsClient.Reply?

    func add(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        if data.isEmpty { finish(); return }   // end of output
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            if let line = String(data: buffer[buffer.startIndex..<newline], encoding: .utf8) { lines.append(line) }
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        if let reply = ClaudeLimitsClient.reply(fromLines: lines) { result = reply; finish() }
    }

    private func finish() { finished = true; semaphore.signal() }

    /// True when the reply arrived before the timeout.
    func wait(timeout: TimeInterval) -> Bool { semaphore.wait(timeout: .now() + timeout) == .success }

    var reply: ClaudeLimitsClient.Reply? { lock.lock(); defer { lock.unlock() }; return result }
}
