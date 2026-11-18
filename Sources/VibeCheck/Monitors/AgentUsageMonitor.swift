import Foundation

/// Token counts in one bucket. "Total" includes cache reads, matching tools as usage tools usually count them.
struct TokenCounts: Equatable {
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0

    var total: Int { input + output + cacheWrite + cacheRead }

    static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(input: a.input + b.input, output: a.output + b.output,
                    cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead)
    }

    static func += (a: inout TokenCounts, b: TokenCounts) { a = a + b }
}

enum AgentKind: String, CaseIterable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var title: String { self == .claude ? "Claude Code" : "Codex" }
}

struct UsageEntry: Equatable {
    var time: Date
    var agent: AgentKind
    var model: String
    var project: String
    var tokens: TokenCounts
}

/// A provider-reported usage limit (Codex writes these into its logs).
struct RateWindow: Equatable {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Date

    var title: String {
        switch windowMinutes {
        case 300: "5-hour limit"
        case 10080: "Weekly limit"
        case let m where m % 1440 == 0: "\(m / 1440)-day limit"
        case let m where m % 60 == 0: "\(m / 60)-hour limit"
        default: "\(windowMinutes)-min limit"
        }
    }
}

/// The current 5-hour window, estimated from local logs the usual way.
struct UsageBlock: Equatable {
    var start: Date
    var end: Date
    var tokens: TokenCounts
}

struct AgentSummary: Equatable, Identifiable {
    var agent: AgentKind
    var today = TokenCounts()
    var week = TokenCounts()
    var block: UsageBlock?
    var limits: [RateWindow] = []
    var lastActive: Date?
    var modelsToday: [(name: String, tokens: Int)] = []
    var id: AgentKind { agent }

    static func == (a: AgentSummary, b: AgentSummary) -> Bool {
        a.agent == b.agent && a.today == b.today && a.week == b.week && a.block == b.block && a.limits == b.limits
            && a.lastActive == b.lastActive && a.modelsToday.map(\.name) == b.modelsToday.map(\.name)
            && a.modelsToday.map(\.tokens) == b.modelsToday.map(\.tokens)
    }
}

struct AgentUsageSample: Equatable {
    /// Only agents that have logs on this Mac.
    var agents: [AgentSummary] = []
    var today = TokenCounts()
    var week = TokenCounts()
    /// Total tokens per hour for the last 24 hours, oldest first.
    var hourly: [Double] = Array(repeating: 0, count: 24)
    var projectsToday: [(name: String, tokens: Int)] = []
    var scanned = false

    static func == (a: AgentUsageSample, b: AgentUsageSample) -> Bool {
        a.agents == b.agents && a.today == b.today && a.week == b.week && a.hourly == b.hourly && a.scanned == b.scanned
            && a.projectsToday.map(\.name) == b.projectsToday.map(\.name)
            && a.projectsToday.map(\.tokens) == b.projectsToday.map(\.tokens)
    }
}

// MARK: - Parsing (pure, testable)

enum AgentLogParser {
    // ISO8601DateFormatter is thread-safe; building one per line would dominate the scan.
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    private static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        return fractional.date(from: string) ?? plain.date(from: string)
    }

    private static func int(_ any: Any?) -> Int { (any as? NSNumber)?.intValue ?? 0 }

    private static func project(_ cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "Unknown" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// One Claude Code transcript line → a usage entry and its dedupe key (message id + request id;
    /// Claude Code can write the same response more than once).
    static func claude(_ line: Data) -> (key: String, entry: UsageEntry)? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let time = date(object["timestamp"] as? String) else { return nil }
        let model = message["model"] as? String ?? "unknown"
        guard model != "<synthetic>" else { return nil }
        let tokens = TokenCounts(input: int(usage["input_tokens"]), output: int(usage["output_tokens"]),
                                 cacheWrite: int(usage["cache_creation_input_tokens"]),
                                 cacheRead: int(usage["cache_read_input_tokens"]))
        guard tokens.total > 0 else { return nil }
        let key = "\(message["id"] as? String ?? UUID().uuidString):\(object["requestId"] as? String ?? "")"
        return (key, UsageEntry(time: time, agent: .claude, model: model,
                                project: project(object["cwd"] as? String), tokens: tokens))
    }

    /// Per-file state while reading a Codex session, which logs running totals rather than per-turn usage.
    struct CodexState {
        var model = "unknown"
        var project = "Unknown"
        var lastTotal: TokenCounts?
    }

    /// One Codex session line → usage since the previous token count, and any rate limits it reports.
    static func codex(_ line: Data, state: inout CodexState) -> (entry: UsageEntry?, limits: [RateWindow]?, time: Date?) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { return (nil, nil, nil) }
        let time = date(object["timestamp"] as? String)
        switch object["type"] as? String {
        case "session_meta", "turn_context":
            if let cwd = payload["cwd"] as? String { state.project = project(cwd) }
            if let model = payload["model"] as? String { state.model = model }
            return (nil, nil, nil)
        case "event_msg" where payload["type"] as? String == "token_count":
            var entry: UsageEntry?
            if let info = payload["info"] as? [String: Any], let total = info["total_token_usage"] as? [String: Any],
               let time {
                let cached = int(total["cached_input_tokens"])
                // Codex counts cached input inside input; output already includes reasoning.
                let now = TokenCounts(input: max(0, int(total["input_tokens"]) - cached),
                                      output: int(total["output_tokens"]),
                                      cacheWrite: int(total["cache_write_input_tokens"]), cacheRead: cached)
                let previous = state.lastTotal ?? TokenCounts()
                let delta = TokenCounts(input: max(0, now.input - previous.input), output: max(0, now.output - previous.output),
                                        cacheWrite: max(0, now.cacheWrite - previous.cacheWrite),
                                        cacheRead: max(0, now.cacheRead - previous.cacheRead))
                state.lastTotal = now
                if delta.total > 0 {
                    entry = UsageEntry(time: time, agent: .codex, model: state.model, project: state.project, tokens: delta)
                }
            }
            var limits: [RateWindow]?
            if let rate = payload["rate_limits"] as? [String: Any] {
                limits = ["primary", "secondary"].compactMap { key -> RateWindow? in
                    guard let window = rate[key] as? [String: Any],
                          let used = (window["used_percent"] as? NSNumber)?.doubleValue else { return nil }
                    return RateWindow(usedPercent: used, windowMinutes: int(window["window_minutes"]),
                                      resetsAt: Date(timeIntervalSince1970: (window["resets_at"] as? NSNumber)?.doubleValue ?? 0))
                }
            }
            return (entry, limits, time)
        default:
            return (nil, nil, nil)
        }
    }

    /// The active 5-hour block: starts at the hour of the first message after a previous block ended
    /// (or after a 5-hour gap), as usage tools usually count them. Nil when the last block is over.
    static func currentBlock(_ entries: [UsageEntry], now: Date, calendar: Calendar = .current) -> UsageBlock? {
        let length: TimeInterval = 5 * 3600
        var block: UsageBlock?
        var last: Date?
        for entry in entries.sorted(by: { $0.time < $1.time }) {
            if let current = block, entry.time < current.end, let last, entry.time.timeIntervalSince(last) < length {
                block?.tokens += entry.tokens
            } else {
                let start = calendar.dateInterval(of: .hour, for: entry.time)?.start ?? entry.time
                block = UsageBlock(start: start, end: start.addingTimeInterval(length), tokens: entry.tokens)
            }
            last = entry.time
        }
        guard let block, now < block.end else { return nil }
        return block
    }

    static func summarize(_ entries: [UsageEntry], limits: [AgentKind: [RateWindow]], present: Set<AgentKind>,
                          now: Date, calendar: Calendar = .current) -> AgentUsageSample {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let firstHour = hourStart.addingTimeInterval(-23 * 3600)
        var sample = AgentUsageSample(scanned: true)
        var projects: [String: Int] = [:]
        for entry in entries where entry.time >= weekStart {
            sample.week += entry.tokens
            if entry.time >= today {
                sample.today += entry.tokens
                projects[entry.project, default: 0] += entry.tokens.total
            }
            if entry.time >= firstHour {
                let index = min(23, Int(entry.time.timeIntervalSince(firstHour) / 3600))
                sample.hourly[index] += Double(entry.tokens.total)
            }
        }
        sample.projectsToday = projects.sorted { $0.value > $1.value }.map { (name: $0.key, tokens: $0.value) }
        for agent in AgentKind.allCases where present.contains(agent) {
            let mine = entries.filter { $0.agent == agent }
            var summary = AgentSummary(agent: agent)
            var models: [String: Int] = [:]
            for entry in mine where entry.time >= weekStart {
                summary.week += entry.tokens
                if entry.time >= today {
                    summary.today += entry.tokens
                    models[entry.model, default: 0] += entry.tokens.total
                }
            }
            summary.modelsToday = models.sorted { $0.value > $1.value }.map { (name: $0.key, tokens: $0.value) }
            summary.lastActive = mine.map(\.time).max()
            if agent == .claude { summary.block = currentBlock(mine.filter { $0.time > now.addingTimeInterval(-24 * 3600) }, now: now, calendar: calendar) }
            summary.limits = (limits[agent] ?? []).filter { $0.resetsAt > now }
            sample.agents.append(summary)
        }
        return sample
    }
}

// MARK: - Scanner

/// Reads agent logs incrementally: remembers how far it got in each file and only looks at files changed in
/// the last week. Everything stays on this Mac. Not thread-safe; use from one serial queue.
final class AgentUsageScanner: @unchecked Sendable {
    private struct FileState {
        var offset: UInt64 = 0
        var codex = AgentLogParser.CodexState()
    }

    private let claudeRoots: [URL]
    private let codexRoots: [URL]
    private var files: [String: FileState] = [:]
    private var entries: [UsageEntry] = []
    private var entryKeys: [String] = []
    private var seen = Set<String>()
    private var limits: (time: Date, windows: [RateWindow])?
    /// Log files found by the last full walk, so quick scans skip walking the folder tree.
    private var known: [(url: URL, agent: AgentKind)] = []
    private var present = Set<AgentKind>()
    private var lastWalk = Date.distantPast
    /// How often the folder tree is walked to find new log files; in between, only known files are checked.
    var walkInterval: TimeInterval = 300

    init(claudeRoots: [URL]? = nil, codexRoots: [URL]? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment
        var claude = [home.appending(path: ".claude/projects"), home.appending(path: ".config/claude/projects")]
        if let dir = env["CLAUDE_CONFIG_DIR"] { claude.append(URL(fileURLWithPath: dir).appending(path: "projects")) }
        self.claudeRoots = claudeRoots ?? claude
        self.codexRoots = codexRoots
            ?? [URL(fileURLWithPath: env["CODEX_HOME"] ?? home.appending(path: ".codex").path).appending(path: "sessions")]
    }

    /// `fullWalk` forces looking for new files now (e.g. when the Agents panel opens).
    func scan(now: Date = Date(), calendar: Calendar = .current, fullWalk: Bool = false) -> AgentUsageSample {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
        if fullWalk || now.timeIntervalSince(lastWalk) >= walkInterval || now < lastWalk {
            lastWalk = now
            present = []
            known = []
            for (agent, roots) in [(AgentKind.claude, claudeRoots), (.codex, codexRoots)] {
                for root in Set(roots.map(\.standardizedFileURL)) {
                    guard FileManager.default.fileExists(atPath: root.path) else { continue }
                    present.insert(agent)
                    known += Self.logFiles(in: root, changedSince: cutoff).map { (url: $0, agent: agent) }
                }
            }
        }
        // Free each file's parsed JSON as we go; on a GCD queue it would otherwise pile up until the scan ends.
        for file in known { autoreleasepool { read(file.url, agent: file.agent) } }
        // Keep one week (plus a day for the 24-hour chart near midnight).
        var keptEntries: [UsageEntry] = [], keptKeys: [String] = []
        for (entry, key) in zip(entries, entryKeys) where entry.time >= cutoff {
            keptEntries.append(entry); keptKeys.append(key)
        }
        entries = keptEntries
        entryKeys = keptKeys
        seen = Set(keptKeys.filter { !$0.isEmpty })
        return AgentLogParser.summarize(entries, limits: limits.map { [.codex: $0.windows] } ?? [:], present: present,
                                        now: now, calendar: calendar)
    }

    private static func logFiles(in root: URL, changedSince cutoff: Date) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  (values.contentModificationDate ?? .distantPast) >= cutoff else { continue }
            result.append(url)
        }
        return result
    }

    private static let usageMarker = Data("\"usage\"".utf8)
    private static let tokenMarker = Data("token_count".utf8)
    private static let contextMarkers = [Data("\"session_meta\"".utf8), Data("\"turn_context\"".utf8)]

    private func read(_ url: URL, agent: AgentKind) {
        var state = files[url.path] ?? FileState()
        // Most files haven't grown since last time; a stat is far cheaper than opening them.
        // (stat, not URL.resourceValues: those are cached on the URL and would never see the file grow.)
        var info = stat()
        if stat(url.path, &info) == 0, UInt64(info.st_size) == state.offset { return }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < state.offset { state = FileState() } // file was replaced
        guard size > state.offset else { files[url.path] = state; return }
        try? handle.seek(toOffset: state.offset)
        guard let data = try? handle.readToEnd(), let lastNewline = data.lastIndex(of: 0x0A) else { return }
        // Only whole lines; a half-written last line is read next time.
        let complete = data[data.startIndex...lastNewline]
        state.offset += UInt64(complete.count)
        for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
            switch agent {
            case .claude:
                guard line.range(of: Self.usageMarker) != nil,
                      let (key, entry) = AgentLogParser.claude(Data(line)), seen.insert(key).inserted else { continue }
                entries.append(entry)
                entryKeys.append(key)
            case .codex:
                guard line.range(of: Self.tokenMarker) != nil || Self.contextMarkers.contains(where: { line.range(of: $0) != nil })
                else { continue }
                let result = AgentLogParser.codex(Data(line), state: &state.codex)
                if let entry = result.entry { entries.append(entry); entryKeys.append("") }
                if let windows = result.limits, let time = result.time, time >= (limits?.time ?? .distantPast) {
                    limits = (time, windows)
                }
            }
        }
        files[url.path] = state
    }
}
