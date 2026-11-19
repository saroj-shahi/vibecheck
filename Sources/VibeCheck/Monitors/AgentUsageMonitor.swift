import Foundation
import SQLite3

/// Token counts in one bucket. "Total" includes cache reads, as usage tools usually count them.
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
    case claude, codex, copilot, opencode
    var id: String { rawValue }
    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .copilot: "GitHub Copilot"
        case .opencode: "OpenCode"
        }
    }
}

struct UsageEntry: Equatable {
    var time: Date
    var agent: AgentKind
    var model: String
    var project: String
    var tokens: TokenCounts
    /// The session it belongs to (the log file for file-based agents); empty when unknown.
    var session: String = ""
}

/// A session that wrote usage in the last two minutes.
struct ActiveSession: Equatable, Identifiable {
    var agent: AgentKind
    var session: String
    var project: String
    var model: String
    var started: Date
    var lastActive: Date
    var tokens: TokenCounts
    var id: String { session }
}

/// Who an agent is signed in as, from the agent's own local files.
struct AgentAccount: Equatable {
    var name: String?
    var plan: String?
}

enum AgentNames {
    /// "claude-opus-5-5" → "Opus 5.5", "claude-sonnet-4-5-20250929" → "Sonnet 4.5"; other models unchanged.
    static func model(_ id: String) -> String {
        guard id.hasPrefix("claude-") else { return id }
        var parts = id.dropFirst("claude-".count).split(separator: "-").map(String.init)
        if let last = parts.last, last.count == 8, Int(last) != nil { parts.removeLast() } // date suffix
        guard let family = parts.first else { return id }
        let version = parts.dropFirst().filter { Int($0) != nil }.joined(separator: ".")
        return family.prefix(1).uppercased() + family.dropFirst() + (version.isEmpty ? "" : " " + version)
    }

    /// Plan labels from Claude Code's `organizationType` or Codex's `plan_type`.
    static func plan(_ raw: String?) -> String? {
        guard var value = raw?.lowercased(), !value.isEmpty else { return nil }
        if value.hasPrefix("claude_") { value.removeFirst("claude_".count) }
        switch value {
        case "free": return "Free"
        case "pro": return "Pro"
        case "max", "max_5x", "max_20x": return "Max"
        case "plus": return "Plus"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu": return "Edu"
        default: return value.prefix(1).uppercased() + value.dropFirst()
        }
    }

    /// Claude Code's `~/.claude.json`: the signed-in name and plan (organizationType). Nothing else is read.
    static func claudeAccount(_ data: Data) -> AgentAccount? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = object["oauthAccount"] as? [String: Any] else { return nil }
        let name = (account["displayName"] as? String) ?? (account["fullName"] as? String)
        return AgentAccount(name: name?.isEmpty == false ? name : nil, plan: plan(account["organizationType"] as? String))
    }

    /// The signed-in email from a `.claude.json` (to tell two Claude Code accounts apart).
    static func claudeEmail(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = object["oauthAccount"] as? [String: Any],
              let email = account["emailAddress"] as? String, !email.isEmpty else { return nil }
        return email
    }
}

/// A provider-reported usage limit (Codex writes these into its logs).
struct RateWindow: Equatable {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Date
    /// Provider's own name for the limit (Copilot: "Chat requests"); otherwise the title comes from the length.
    var name: String? = nil

    var title: String { name ?? lengthTitle }

    private var lengthTitle: String {
        switch windowMinutes {
        case 300: String(localized: "5-hour limit")
        case 10080: String(localized: "Weekly limit")
        case 40320...44640: String(localized: "Monthly limit")
        case let m where m % 1440 == 0: String(localized: "\(String(m / 1440))-day limit")
        case let m where m % 60 == 0: String(localized: "\(String(m / 60))-hour limit")
        default: String(localized: "\(String(windowMinutes))-min limit")
        }
    }
}

extension RateWindow {
    var start: Date { resetsAt.addingTimeInterval(-Double(windowMinutes) * 60) }
    /// Unique within one agent's limits (two monthly quotas share a length, so the name is part of it).
    var key: String { "\(windowMinutes):\(title)" }
    var leftPercent: Double { min(max(100 - usedPercent, 0), 100) }

    /// "Current session" for the 5-hour window, otherwise the plain title.
    var cardTitle: String { windowMinutes == 300 ? String(localized: "Current session") : title }

    /// How far through the window we are, 0–1.
    func elapsedFraction(now: Date) -> Double {
        let span = Double(windowMinutes) * 60
        guard span > 0 else { return 0 }
        return min(max(now.timeIntervalSince(start) / span, 0), 1)
    }

    /// Average use since the window started, in percent per hour. Nil in the first few minutes
    /// (too little time to mean anything) or once the window is over.
    func burnPerHour(now: Date) -> Double? {
        let hours = now.timeIntervalSince(start) / 3600
        guard hours >= 0.1, now < resetsAt else { return nil }
        return usedPercent / hours
    }

    /// Using the limit faster than time passes (with a little slack), so it runs out before it resets.
    func isAheadOfPace(now: Date) -> Bool {
        usedPercent / 100 > elapsedFraction(now: now) + 0.05
    }

    /// Burn rate as shown: per hour for windows up to a week, per day for longer ones ("0.3%/day").
    func burnText(now: Date) -> String? {
        guard let perHour = burnPerHour(now: now) else { return nil }
        return windowMinutes > 10080 ? String(localized: "\(String(format: "%.1f", perHour * 24))%/day") : String(localized: "\(String(format: "%.1f", perHour))%/hr")
    }

    /// "2h 42m", "5d 22h", "18m", "now".
    func countdown(now: Date) -> String {
        let minutes = Int(max(resetsAt.timeIntervalSince(now), 0) / 60)
        switch minutes {
        case 0: return "now"
        case ..<60: return "\(minutes)m"
        case ..<1440: return "\(minutes / 60)h \(minutes % 60)m"
        default: return "\(minutes / 1440)d \((minutes % 1440) / 60)h"
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
    var account = AgentAccount()
    var id: AgentKind { agent }

    /// Wrote usage in the last two minutes: a session is most likely running right now.
    func isWorking(now: Date) -> Bool {
        lastActive.map { now.timeIntervalSince($0) < 120 } ?? false
    }

    static func == (a: AgentSummary, b: AgentSummary) -> Bool {
        a.agent == b.agent && a.today == b.today && a.week == b.week && a.block == b.block && a.limits == b.limits
            && a.lastActive == b.lastActive && a.account == b.account && a.modelsToday.map(\.name) == b.modelsToday.map(\.name)
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
    /// Total tokens per day for the last 7 days (today last).
    var daily: [Double] = Array(repeating: 0, count: 7)
    /// Tokens in the last 60 minutes (the tokens-per-hour alert).
    var lastHour = 0
    /// Sessions that wrote usage in the last two minutes, most recent first.
    var activeSessions: [ActiveSession] = []
    var projectsToday: [(name: String, tokens: Int)] = []
    var scanned = false
    /// Every agent with logs on this Mac, including ones switched off in Settings (`agents` leaves those out).
    var found: Set<AgentKind> = []

    static func == (a: AgentUsageSample, b: AgentUsageSample) -> Bool {
        a.agents == b.agents && a.found == b.found && a.today == b.today && a.week == b.week && a.hourly == b.hourly && a.scanned == b.scanned
            && a.daily == b.daily && a.lastHour == b.lastHour && a.activeSessions == b.activeSessions
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
        /// `plan_type` from the latest rate limits ("free", "plus", …).
        var plan: String?
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
                if let plan = rate["plan_type"] as? String { state.plan = plan }
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

    /// Per-file state while reading a Copilot CLI session (`events.jsonl`).
    struct CopilotState {
        var project = "Unknown"
    }

    /// One Copilot CLI event → a usage entry (with its event id for dedupe) and/or the monthly quotas.
    /// Copilot talks to OpenAI-style endpoints: input includes cache reads and output includes reasoning.
    static func copilot(_ line: Data, state: inout CopilotState, calendar: Calendar = .current)
        -> (key: String?, entry: UsageEntry?, limits: [RateWindow]?, time: Date?) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let data = object["data"] as? [String: Any] else { return (nil, nil, nil, nil) }
        let time = date(object["timestamp"] as? String)
        switch object["type"] as? String {
        case "session.start", "session.resume":
            if let context = data["context"] as? [String: Any], let cwd = context["cwd"] as? String {
                state.project = project(cwd)
            }
            return (nil, nil, nil, nil)
        case "session.usage_record":
            guard let usage = data["usage"] as? [String: Any], let time else { return (nil, nil, nil, nil) }
            let cacheRead = int(usage["cacheReadTokens"])
            let tokens = TokenCounts(input: max(0, int(usage["inputTokens"]) - cacheRead), output: int(usage["outputTokens"]),
                                     cacheWrite: int(usage["cacheWriteTokens"]), cacheRead: cacheRead)
            guard tokens.total > 0 else { return (nil, nil, nil, nil) }
            let model = usage["model"] as? String ?? "unknown"
            return (object["id"] as? String, UsageEntry(time: time, agent: .copilot, model: model,
                                                        project: state.project, tokens: tokens), nil, time)
        case "model.model_call_success":
            guard let quotas = data["quotaSnapshots"] as? [String: Any] else { return (nil, nil, nil, nil) }
            let names = [("chat", String(localized: "Chat requests")), ("completions", String(localized: "Completions")), ("premium_interactions", String(localized: "Premium requests"))]
            let windows = names.compactMap { key, name -> RateWindow? in
                guard let quota = quotas[key] as? [String: Any],
                      quota["isUnlimitedEntitlement"] as? Bool != true, int(quota["entitlementRequests"]) > 0,
                      let left = (quota["remainingPercentage"] as? NSNumber)?.doubleValue,
                      let reset = date(quota["resetDate"] as? String),
                      let start = calendar.date(byAdding: .month, value: -1, to: reset) else { return nil }
                return RateWindow(usedPercent: min(max(100 - left, 0), 100),
                                  windowMinutes: Int(reset.timeIntervalSince(start) / 60), resetsAt: reset, name: name)
            }
            return (nil, nil, windows.isEmpty ? nil : windows, time)
        default:
            return (nil, nil, nil, nil)
        }
    }

    /// One OpenCode message row (`message.data` JSON) → a usage entry. Reasoning is counted as output.
    static func opencode(_ data: Data) -> UsageEntry? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["role"] as? String == "assistant",
              let tokens = object["tokens"] as? [String: Any],
              let created = ((object["time"] as? [String: Any])?["created"] as? NSNumber)?.doubleValue else { return nil }
        let cache = tokens["cache"] as? [String: Any] ?? [:]
        let counts = TokenCounts(input: int(tokens["input"]), output: int(tokens["output"]) + int(tokens["reasoning"]),
                                 cacheWrite: int(cache["write"]), cacheRead: int(cache["read"]))
        guard counts.total > 0 else { return nil }
        let path = object["path"] as? [String: Any]
        return UsageEntry(time: Date(timeIntervalSince1970: created / 1000), agent: .opencode,
                          model: object["modelID"] as? String ?? "unknown",
                          project: project(path?["cwd"] as? String), tokens: counts)
    }

    /// The active 5-hour block: starts at the hour of the first message after a previous block ended
    /// (or after a 5-hour gap). Nil when the last block is over.
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
                          now: Date, calendar: Calendar = .current,
                          accounts: [AgentKind: AgentAccount] = [:]) -> AgentUsageSample {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let firstHour = hourStart.addingTimeInterval(-23 * 3600)
        var sample = AgentUsageSample(scanned: true)
        var projects: [String: Int] = [:]
        let hourAgo = now.addingTimeInterval(-3600)
        for entry in entries where entry.time >= weekStart {
            sample.week += entry.tokens
            let day = calendar.dateComponents([.day], from: weekStart, to: calendar.startOfDay(for: entry.time)).day ?? -1
            if (0..<7).contains(day) { sample.daily[day] += Double(entry.tokens.total) }
            if entry.time >= hourAgo, entry.time <= now { sample.lastHour += entry.tokens.total }
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
            summary.account = accounts[agent] ?? AgentAccount()
            sample.agents.append(summary)
        }
        sample.activeSessions = activeSessions(entries, now: now)
        return sample
    }

    /// Sessions whose last usage is under two minutes old, with their totals since they started.
    static func activeSessions(_ entries: [UsageEntry], now: Date) -> [ActiveSession] {
        var sessions: [String: ActiveSession] = [:]
        for entry in entries where !entry.session.isEmpty && entry.time <= now {
            if var s = sessions[entry.session] {
                s.tokens += entry.tokens
                s.started = min(s.started, entry.time)
                if entry.time >= s.lastActive { s.lastActive = entry.time; s.model = entry.model; s.project = entry.project }
                sessions[entry.session] = s
            } else {
                sessions[entry.session] = ActiveSession(agent: entry.agent, session: entry.session, project: entry.project,
                                                        model: entry.model, started: entry.time, lastActive: entry.time,
                                                        tokens: entry.tokens)
            }
        }
        return sessions.values.filter { now.timeIntervalSince($0.lastActive) < 120 }
            .sorted { $0.lastActive > $1.lastActive }
    }
}

// MARK: - Scanner

/// Reads agent logs incrementally: remembers how far it got in each file and only looks at files changed in
/// the last week. Everything stays on this Mac. Not thread-safe; use from one serial queue.
final class AgentUsageScanner: @unchecked Sendable {
    private struct FileState {
        var offset: UInt64 = 0
        var codex = AgentLogParser.CodexState()
        var copilot = AgentLogParser.CopilotState()
    }

    private let claudeRoots: [URL]
    private let codexRoots: [URL]
    private let copilotRoots: [URL]
    private let opencodeDB: URL
    private let claudeConfig: URL
    /// Names and plans, refreshed on each full walk.
    private var accounts: [AgentKind: AgentAccount] = [:]
    /// Codex's plan from its newest rate limits.
    private var codexPlan: String?
    /// Modification stamp of the OpenCode database (and its WAL) at the last read; nil = never read.
    private var opencodeStamp: String?
    private var files: [String: FileState] = [:]
    private var entries: [UsageEntry] = []
    private var entryKeys: [String] = []
    private var seen = Set<String>()
    /// Latest provider-reported limits per agent (Codex and Copilot log them).
    private var limits: [AgentKind: (time: Date, windows: [RateWindow])] = [:]
    /// Log files found by the last full walk, so quick scans skip walking the folder tree.
    private var known: [(url: URL, agent: AgentKind)] = []
    private var present = Set<AgentKind>()
    private var lastWalk = Date.distantPast
    /// How often the folder tree is walked to find new log files; in between, only known files are checked.
    var walkInterval: TimeInterval = 300

    init(claudeRoots: [URL]? = nil, codexRoots: [URL]? = nil, copilotRoots: [URL]? = nil, opencodeDB: URL? = nil,
         claudeConfig: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment
        var claude = [home.appending(path: ".claude/projects"), home.appending(path: ".config/claude/projects")]
        if let dir = env["CLAUDE_CONFIG_DIR"] { claude.append(URL(fileURLWithPath: dir).appending(path: "projects")) }
        self.claudeRoots = claudeRoots ?? claude
        self.codexRoots = codexRoots
            ?? [URL(fileURLWithPath: env["CODEX_HOME"] ?? home.appending(path: ".codex").path).appending(path: "sessions")]
        self.copilotRoots = copilotRoots
            ?? [URL(fileURLWithPath: env["COPILOT_HOME"] ?? home.appending(path: ".copilot").path).appending(path: "session-state")]
        let dataHome = env["XDG_DATA_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appending(path: ".local/share")
        self.opencodeDB = opencodeDB ?? dataHome.appending(path: "opencode/opencode.db")
        self.claudeConfig = claudeConfig
            ?? (env["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? home).appending(path: ".claude.json")
    }

    /// `fullWalk` forces looking for new files now (e.g. when the Agents panel opens). `shown` leaves the other
    /// agents out of every total, chart and list (they're still read, so switching one back on is instant).
    func scan(now: Date = Date(), calendar: Calendar = .current, fullWalk: Bool = false,
              shown: Set<AgentKind> = Set(AgentKind.allCases)) -> AgentUsageSample {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
        if fullWalk || now.timeIntervalSince(lastWalk) >= walkInterval || now < lastWalk {
            lastWalk = now
            present = []
            known = []
            if FileManager.default.fileExists(atPath: opencodeDB.path) { present.insert(.opencode) }
            accounts[.claude] = (try? Data(contentsOf: claudeConfig)).flatMap(AgentNames.claudeAccount)
            for (agent, roots) in [(AgentKind.claude, claudeRoots), (.codex, codexRoots), (.copilot, copilotRoots)] {
                for root in Set(roots.map(\.standardizedFileURL)) {
                    guard FileManager.default.fileExists(atPath: root.path) else { continue }
                    present.insert(agent)
                    var files = Self.logFiles(in: root, changedSince: cutoff)
                    // Copilot's monthly quota lives in its session logs: read the newest one even when it's older
                    // than a week (its usage is dropped below; the quota is shown until it resets).
                    if agent == .copilot, files.isEmpty, let newest = Self.logFiles(in: root, changedSince: .distantPast)
                        .max(by: { Self.modified($0) < Self.modified($1) }) {
                        files.append(newest)
                    }
                    known += files.map { (url: $0, agent: agent) }
                }
            }
        }
        // Free each file's parsed JSON as we go; on a GCD queue it would otherwise pile up until the scan ends.
        for file in known { autoreleasepool { read(file.url, agent: file.agent) } }
        if present.contains(.opencode) { autoreleasepool { readOpenCode(since: cutoff) } }
        // Keep one week (plus a day for the 24-hour chart near midnight).
        var keptEntries: [UsageEntry] = [], keptKeys: [String] = []
        for (entry, key) in zip(entries, entryKeys) where entry.time >= cutoff {
            keptEntries.append(entry); keptKeys.append(key)
        }
        entries = keptEntries
        entryKeys = keptKeys
        seen = Set(keptKeys.filter { !$0.isEmpty })
        var accounts = self.accounts
        if let codexPlan { accounts[.codex] = AgentAccount(plan: AgentNames.plan(codexPlan)) }
        var sample = AgentLogParser.summarize(entries.filter { shown.contains($0.agent) },
                                              limits: limits.mapValues(\.windows).filter { shown.contains($0.key) },
                                              present: present.intersection(shown),
                                              now: now, calendar: calendar, accounts: accounts)
        sample.found = present
        return sample
    }

    private static func modified(_ url: URL) -> Date {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return .distantPast }
        return Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
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
    private static let copilotMarkers = ["session.usage_record", "quotaSnapshots", "session.start", "session.resume"].map { Data($0.utf8) }

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
                      let (key, parsed) = AgentLogParser.claude(Data(line)), seen.insert(key).inserted else { continue }
                var entry = parsed
                entry.session = url.path
                entries.append(entry)
                entryKeys.append(key)
            case .codex:
                guard line.range(of: Self.tokenMarker) != nil || Self.contextMarkers.contains(where: { line.range(of: $0) != nil })
                else { continue }
                let result = AgentLogParser.codex(Data(line), state: &state.codex)
                if var entry = result.entry { entry.session = url.path; entries.append(entry); entryKeys.append("") }
                if let windows = result.limits, let time = result.time, keepLimits(windows, at: time, for: .codex) {
                    codexPlan = state.codex.plan ?? codexPlan
                }
            case .copilot:
                guard Self.copilotMarkers.contains(where: { line.range(of: $0) != nil }) else { continue }
                let result = AgentLogParser.copilot(Data(line), state: &state.copilot)
                if var entry = result.entry {
                    entry.session = url.path
                    let key = result.key.map { "copilot:" + $0 } ?? ""
                    if key.isEmpty || seen.insert(key).inserted { entries.append(entry); entryKeys.append(key) }
                }
                if let windows = result.limits, let time = result.time { keepLimits(windows, at: time, for: .copilot) }
            case .opencode:
                continue // read from its database, not from log files
            }
        }
        files[url.path] = state
    }

    /// Keeps `windows` if they're the newest seen for `agent`; returns whether they were.
    @discardableResult
    private func keepLimits(_ windows: [RateWindow], at time: Date, for agent: AgentKind) -> Bool {
        guard time >= (limits[agent]?.time ?? .distantPast) else { return false }
        limits[agent] = (time, windows)
        return true
    }

    /// OpenCode keeps messages in SQLite. When the database (or its WAL) changed, re-read the week's
    /// assistant messages and replace all OpenCode entries (token counts are filled in after a message starts).
    private func readOpenCode(since cutoff: Date) {
        let paths = [opencodeDB.path, opencodeDB.path + "-wal"]
        let stamp = paths.map { path -> String in
            var info = stat()
            guard stat(path, &info) == 0 else { return "-" }
            return "\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)"
        }.joined(separator: "|")
        guard stamp != opencodeStamp else { return }
        guard let rows = Self.openCodeMessages(at: opencodeDB, since: cutoff) else { return }
        opencodeStamp = stamp
        var keptEntries: [UsageEntry] = [], keptKeys: [String] = []
        for (entry, key) in zip(entries, entryKeys) where entry.agent != .opencode {
            keptEntries.append(entry); keptKeys.append(key)
        }
        for (id, data) in rows {
            guard let entry = AgentLogParser.opencode(data) else { continue }
            keptEntries.append(entry); keptKeys.append("opencode:" + id)
        }
        entries = keptEntries
        entryKeys = keptKeys
    }

    /// Read-only query; nil if the database can't be opened right now (it's retried next scan).
    static func openCodeMessages(at url: URL, since cutoff: Date) -> [(id: String, data: Data)]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)
        var statement: OpaquePointer?
        let sql = "SELECT id, data FROM message WHERE time_created >= ?"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(cutoff.timeIntervalSince1970 * 1000))
        var rows: [(id: String, data: Data)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = sqlite3_column_text(statement, 0), let bytes = sqlite3_column_blob(statement, 1) else { continue }
            let count = Int(sqlite3_column_bytes(statement, 1))
            rows.append((String(cString: id), Data(bytes: bytes, count: count)))
        }
        return rows
    }
}
