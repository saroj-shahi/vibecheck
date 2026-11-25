import Foundation

/// Per-item menu bar options, beyond the look (`LabelStyle`). One value per module; each module only reads
/// the fields that apply to it. Stored as JSON in the `itemOptions` defaults key and part of settings backup.
struct ItemOptions: Codable, Equatable {
    // Agents
    /// Agents counted by the item. Empty means all.
    var agents: Set<AgentKind> = []
    var agentValue: AgentValue = .tokensToday
    var agentWindows: AgentWindows = .both
    var agentShowReset = true
    /// Show when the limit runs out (at the current pace) in place of the reset countdown, while it would run out.
    var agentShowRunOut = false

    // Memory
    var memoryValue: MemoryValue = .percent

    // Network
    var networkDirections: Directions = .both

    // Disk
    var diskValue: DiskValue = .rates

    // Battery
    var batteryValue: BatteryValue = .percent

    // Sensors
    var sensorUnit: TemperatureUnit = .celsius

    init() {}

    /// Decodes whatever fields are present, so options saved by an older version keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ItemOptions()
        agents = try c.decodeIfPresent(Set<AgentKind>.self, forKey: .agents) ?? d.agents
        agentValue = (try? c.decodeIfPresent(AgentValue.self, forKey: .agentValue)) ?? d.agentValue
        agentWindows = (try? c.decodeIfPresent(AgentWindows.self, forKey: .agentWindows)) ?? d.agentWindows
        agentShowReset = try c.decodeIfPresent(Bool.self, forKey: .agentShowReset) ?? d.agentShowReset
        agentShowRunOut = try c.decodeIfPresent(Bool.self, forKey: .agentShowRunOut) ?? d.agentShowRunOut
        memoryValue = (try? c.decodeIfPresent(MemoryValue.self, forKey: .memoryValue)) ?? d.memoryValue
        networkDirections = (try? c.decodeIfPresent(Directions.self, forKey: .networkDirections)) ?? d.networkDirections
        diskValue = (try? c.decodeIfPresent(DiskValue.self, forKey: .diskValue)) ?? d.diskValue
        batteryValue = (try? c.decodeIfPresent(BatteryValue.self, forKey: .batteryValue)) ?? d.batteryValue
        sensorUnit = (try? c.decodeIfPresent(TemperatureUnit.self, forKey: .sensorUnit)) ?? d.sensorUnit
    }

    /// Whether `kind` is counted (empty selection = all).
    func includes(_ kind: AgentKind) -> Bool { agents.isEmpty || agents.contains(kind) }

    /// Turns one agent on or off for the item; all on is stored as "all" (empty) so new agents show up too.
    mutating func setAgent(_ kind: AgentKind, shown: Bool) {
        var set = agents.isEmpty ? Set(AgentKind.allCases) : agents
        if shown { set.insert(kind) } else { set.remove(kind) }
        guard !set.isEmpty else { return }
        agents = set == Set(AgentKind.allCases) ? [] : set
    }

    /// Modules that have options beyond the look.
    static func hasOptions(_ module: Module) -> Bool {
        [.agents, .memory, .network, .disk, .battery, .sensors].contains(module)
    }

    enum AgentValue: String, Codable, CaseIterable, Identifiable {
        case limitsLeft, limitsUsed, tokensToday, tokensWeek, tokensWindow
        var id: String { rawValue }
        var title: String {
            switch self {
            case .limitsLeft: String(localized: "Limits: % left")
            case .limitsUsed: String(localized: "Limits: % used")
            case .tokensToday: String(localized: "Tokens today")
            case .tokensWeek: String(localized: "Tokens this week")
            case .tokensWindow: String(localized: "Tokens this 5-hour window")
            }
        }
        var isLimits: Bool { self == .limitsLeft || self == .limitsUsed }
    }

    enum AgentWindows: String, Codable, CaseIterable, Identifiable {
        case both, session, longest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .both: String(localized: "Session and weekly")
            case .session: String(localized: "Current session only")
            case .longest: String(localized: "Weekly (or monthly) only")
            }
        }
    }

    enum MemoryValue: String, Codable, CaseIterable, Identifiable {
        case percent, used, free
        var id: String { rawValue }
        var title: String {
            switch self {
            case .percent: String(localized: "Percent used")
            case .used: String(localized: "Amount used")
            case .free: String(localized: "Amount free")
            }
        }
    }

    enum Directions: String, Codable, CaseIterable, Identifiable {
        case both, download, upload
        var id: String { rawValue }
        var title: String {
            switch self {
            case .both: String(localized: "Upload and download")
            case .download: String(localized: "Download only")
            case .upload: String(localized: "Upload only")
            }
        }
    }

    enum DiskValue: String, Codable, CaseIterable, Identifiable {
        case rates, free
        var id: String { rawValue }
        var title: String { self == .rates ? String(localized: "Read and write rates") : String(localized: "Startup disk free space") }
    }

    enum BatteryValue: String, Codable, CaseIterable, Identifiable {
        case percent, time, both
        var id: String { rawValue }
        var title: String {
            switch self {
            case .percent: String(localized: "Percent")
            case .time: String(localized: "Time remaining")
            case .both: String(localized: "Percent and time")
            }
        }
    }
}

extension AgentKind: Codable {}
extension TemperatureUnit: Codable {}

extension AgentUsageSample {
    /// The agents an item counts, in `AgentKind` order.
    func agents(for options: ItemOptions) -> [AgentSummary] {
        agents.filter { options.includes($0.agent) }
    }

    /// What the agents item shows for `options`. Limits come from the first counted agent that reports
    /// them (Claude Code first); otherwise the first counted agent with a local 5-hour estimate (Claude Code
    /// or Antigravity); otherwise tokens.
    func menuBarContent(_ options: ItemOptions) -> AgentMenuContent {
        let counted = agents(for: options)
        if options.agentValue.isLimits {
            if let withLimits = counted.first(where: { !$0.limits.isEmpty }) {
                let sorted = withLimits.limits.sorted { $0.windowMinutes < $1.windowMinutes }
                let shortest = sorted[0]
                // Prefer the first window of each distinct length so multi-group limits (e.g. Antigravity's
                // Gemini + Claude & GPT pools, or Claude's overall + Opus/Sonnet weekly) show primary session + weekly.
                let longest = sorted.first { $0.windowMinutes == sorted[sorted.count - 1].windowMinutes } ?? sorted[sorted.count - 1]
                let windows: [RateWindow]
                switch options.agentWindows {
                case .both:
                    if let longer = sorted.first(where: { $0.windowMinutes > shortest.windowMinutes }) {
                        windows = [shortest, longer]
                    } else {
                        windows = Array(sorted.prefix(2))
                    }
                case .session: windows = [shortest]
                case .longest: windows = [longest]
                }
                return .limits(windows, used: options.agentValue == .limitsUsed)
            }
            if let estimated = counted.first(where: { $0.block != nil }), let block = estimated.block {
                return .windowEstimate(estimated.agent, block, today: estimated.today.total)
            }
        }
        let total: Int = switch options.agentValue {
        case .tokensWeek: counted.reduce(0) { $0 + $1.week.total }
        case .tokensWindow: counted.compactMap(\.block?.tokens.total).reduce(0, +)
        default: counted.reduce(0) { $0 + $1.today.total }
        }
        return .tokens(total)
    }
}

extension AgentUsageSample {
    /// Whose logo the agents item draws: the agent the number comes from (limits or a local 5-hour estimate),
    /// else the busiest counted agent for the chosen value, else the first counted one (Claude Code before any scan).
    func menuBarAgent(_ options: ItemOptions) -> AgentKind {
        let counted = agents(for: options)
        if options.agentValue.isLimits {
            if let withLimits = counted.first(where: { !$0.limits.isEmpty }) { return withLimits.agent }
            if let estimated = counted.first(where: { $0.block != nil }) { return estimated.agent }
        }
        func value(_ a: AgentSummary) -> Int {
            switch options.agentValue {
            case .tokensWeek: a.week.total
            case .tokensWindow: a.block?.tokens.total ?? 0
            default: a.today.total
            }
        }
        if let busiest = counted.max(by: { value($0) < value($1) }), value(busiest) > 0 { return busiest.agent }
        return counted.first?.agent ?? AgentKind.allCases.first(where: options.includes) ?? .claude
    }
}

/// What the agents menu bar item draws.
enum AgentMenuContent: Equatable {
    case limits([RateWindow], used: Bool)
    case windowEstimate(AgentKind, UsageBlock, today: Int)
    case tokens(Int)
}
