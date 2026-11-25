import Foundation
import Observation

/// Opt-in: asks the user's own Antigravity CLI (`agy`) for Antigravity's real plan limits (5-hour and weekly)
/// and hands them to the Agents module. `agy` signs in itself; no Keychain access, no network request from
/// this app, no model request (`num_turns: 0`).
@Observable
@MainActor
final class AntigravityLiveLimits {
    static let shared = AntigravityLiveLimits()
    nonisolated static let defaultsKey = "antigravityLiveLimits"
    /// Live limits older than this are ignored.
    nonisolated static let staleAfter: TimeInterval = 15 * 60
    nonisolated static let normalInterval: TimeInterval = 5 * 60
    nonisolated static let errorInterval: TimeInterval = 15 * 60

    enum Outcome: Equatable { case none, live, notInstalled, signedOut, noAnswer }

    var isOn: Bool = UserDefaults.standard.bool(forKey: AntigravityLiveLimits.defaultsKey) {
        didSet {
            guard oldValue != isOn else { return }
            UserDefaults.standard.set(isOn, forKey: Self.defaultsKey)
            updateTimer()
            if isOn { lastAttempt = .distantPast; outcome = .none; tick() } else { AgentUsageStore.shared.reapply() }
        }
    }

    private(set) var windows: [RateWindow] = []
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
            MainActor.assumeIsolated { AntigravityLiveLimits.shared.tick() }
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
        Task {
            let result = await Task.detached(priority: .utility) { AntigravityLimitsClient.fetch() }.value
            AntigravityLiveLimits.shared.finish(result)
        }
    }

    private func finish(_ result: AntigravityLimitsClient.Result) {
        fetching = false
        guard isOn else { return }
        switch result {
        case .usage(let list):
            windows = list
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
        case .notInstalled: return String(localized: "Antigravity CLI isn't installed")
        case .signedOut: return String(localized: "Antigravity CLI is signed out")
        case .noAnswer: return String(localized: "Antigravity CLI didn't answer")
        case .live:
            guard let fetchedAt else { return String(localized: "Waiting for the first update") }
            let minutes = max(0, Int(now.timeIntervalSince(fetchedAt) / 60))
            return minutes == 0
                ? String(localized: "Live from Antigravity CLI · updated just now")
                : String(localized: "Live from Antigravity CLI · updated \(String(minutes)) min ago")
        }
    }

    /// Pure merge rule: fresh live limits replace Antigravity's limits; everything else is left as is.
    nonisolated static func merge(_ sample: AgentUsageSample, live: [RateWindow], fetchedAt: Date?, now: Date) -> AgentUsageSample {
        let live = live.filter { $0.resetsAt > now }
        guard !live.isEmpty, let fetchedAt, now.timeIntervalSince(fetchedAt) < staleAfter,
              let index = sample.agents.firstIndex(where: { $0.agent == .antigravity }) else { return sample }
        var merged = sample
        merged.agents[index].limits = live
        return merged
    }
}

/// Runs the user's Antigravity CLI (`agy`) to read plan usage via `/usage`. Only called when the setting is on.
enum AntigravityLimitsClient {
    enum Result: Sendable, Equatable {
        case usage([RateWindow])
        case notInstalled
        case signedOut
        case noAnswer
    }

    /// Parsed `/usage` response, reduced to what we show.
    struct Usage: Equatable {
        var windows: [RateWindow]
        /// True when `agy` returned a successful `/usage` payload.
        var available: Bool
    }

    nonisolated static let timeout: TimeInterval = 30
    nonisolated static let arguments = ["--print", "/usage", "--output-format", "json", "--print-timeout", "25s"]

    /// First executable `agy` in the usual install locations.
    nonisolated static func findCLI(home: String = NSHomeDirectory(), fileManager: FileManager = .default) -> URL? {
        let candidates = [home + "/.local/bin/agy", "/opt/homebrew/bin/agy", "/usr/local/bin/agy"]
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// Blocking; call off the main thread. Hard 30 s limit for the whole run.
    nonisolated static func fetch() -> Result {
        guard let cli = findCLI() else { return .notInstalled }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vibecheck-agy-" + UUID().uuidString)
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return .noAnswer }
        defer { try? FileManager.default.removeItem(at: directory) }

        let process = Process()
        process.executableURL = cli
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        let output = Pipe(), errorOutput = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errorOutput

        let stdout = OutputCollector(), stderr = OutputCollector()
        output.fileHandleForReading.readabilityHandler = { stdout.append($0.availableData) }
        errorOutput.fileHandleForReading.readabilityHandler = { stderr.append($0.availableData) }
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }

        do { try process.run() } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errorOutput.fileHandleForReading.readabilityHandler = nil
            return .noAnswer
        }

        let finished = done.wait(timeout: .now() + timeout) == .success
        if !finished, process.isRunning {
            process.terminate()
            _ = done.wait(timeout: .now() + 2)
        }
        output.fileHandleForReading.readabilityHandler = nil
        errorOutput.fileHandleForReading.readabilityHandler = nil
        guard finished else { return .noAnswer }
        stdout.append(output.fileHandleForReading.readDataToEndOfFile())
        stderr.append(errorOutput.fileHandleForReading.readDataToEndOfFile())

        return classify(stdout: stdout.data, stderr: stderr.data, exitCode: process.terminationStatus)
    }

    /// Maps process output to a fetch result. Pure and testable.
    nonisolated static func classify(stdout: Data, stderr: Data, exitCode: Int32) -> Result {
        if exitCode == 0 {
            let usage = parse(stdout)
            if usage.available {
                return usage.windows.isEmpty ? .noAnswer : .usage(usage.windows)
            }
        }
        return isSignedOut(stdout: stdout, stderr: stderr) ? .signedOut : .noAnswer
    }

    /// Pure parse of the `agy --print /usage --output-format json` payload.
    nonisolated static func parse(_ data: Data) -> Usage {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["status"] as? String)?.uppercased() == "SUCCESS",
              let command = object["command"] as? [String: Any],
              command["name"] as? String == "usage",
              let payload = command["data"] as? [String: Any],
              let groups = payload["groups"] as? [[String: Any]] else {
            return Usage(windows: [], available: false)
        }

        let multipleGroups = groups.count > 1
        var windows: [RateWindow] = []
        for group in groups {
            let groupName = (group["name"] as? String) ?? ""
            let label = shortGroupLabel(groupName)
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }
            var groupWindows: [RateWindow] = []
            for bucket in buckets {
                guard let minutes = windowMinutes(bucket["window"] as? String),
                      let remaining = (bucket["remaining_fraction"] as? NSNumber)?.doubleValue, remaining.isFinite,
                      let reset = ClaudeLimitsClient.date(bucket["reset_time"] as? String) else { continue }
                let used = min(max((1 - remaining) * 100, 0), 100)
                let name: String? = multipleGroups && !label.isEmpty ? windowName(minutes: minutes, group: label) : nil
                groupWindows.append(RateWindow(usedPercent: used, windowMinutes: minutes, resetsAt: reset, name: name))
            }
            groupWindows.sort { $0.windowMinutes < $1.windowMinutes }
            windows.append(contentsOf: groupWindows)
        }
        return Usage(windows: windows, available: true)
    }

    /// Short display label for an Antigravity model group ("Gemini Models" → "Gemini",
    /// "Claude and GPT models" → "Claude & GPT").
    nonisolated static func shortGroupLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "gemini models": return String(localized: "Gemini")
        case "claude and gpt models": return String(localized: "Claude & GPT")
        default:
            if trimmed.lowercased().hasSuffix(" models") {
                return String(trimmed.dropLast(" models".count)).trimmingCharacters(in: .whitespaces)
            }
            return trimmed
        }
    }

    nonisolated static func windowMinutes(_ raw: String?) -> Int? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else { return nil }
        switch value {
        case "5h": return 300
        case "daily", "24h": return 1440
        case "weekly": return 10080
        case "monthly": return 43200
        default:
            if value.hasSuffix("h"), let hours = Int(value.dropLast()), hours > 0 { return hours * 60 }
            if value.hasSuffix("d"), let days = Int(value.dropLast()), days > 0 { return days * 1440 }
            if value.hasSuffix("m"), let mins = Int(value.dropLast()), mins > 0 { return mins }
            return nil
        }
    }

    private nonisolated static func windowName(minutes: Int, group: String) -> String {
        switch minutes {
        case 300: return String(localized: "5-hour · \(group)")
        case 10080: return String(localized: "Weekly · \(group)")
        case let m where m % 1440 == 0: return String(localized: "\(String(m / 1440))-day · \(group)")
        case let m where m % 60 == 0: return String(localized: "\(String(m / 60))-hour · \(group)")
        default: return String(localized: "\(String(minutes))-min · \(group)")
        }
    }

    private nonisolated static func isSignedOut(stdout: Data, stderr: Data) -> Bool {
        let combined = ((String(data: stdout, encoding: .utf8) ?? "") + "\n" + (String(data: stderr, encoding: .utf8) ?? "")).lowercased()
        let hints = ["not logged in", "not signed in", "sign in", "log in", "login required",
                     "unauthenticated", "unauthorized", "authentication required", "credentials"]
        return hints.contains { combined.contains($0) }
    }
}

/// Thread-safe byte accumulator for subprocess pipe output.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        buffer.append(chunk)
    }

    var data: Data { lock.lock(); defer { lock.unlock() }; return buffer }
}
