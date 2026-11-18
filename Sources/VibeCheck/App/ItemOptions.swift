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
        memoryValue = (try? c.decodeIfPresent(MemoryValue.self, forKey: .memoryValue)) ?? d.memoryValue
        networkDirections = (try? c.decodeIfPresent(Directions.self, forKey: .networkDirections)) ?? d.networkDirections
        diskValue = (try? c.decodeIfPresent(DiskValue.self, forKey: .diskValue)) ?? d.diskValue
        batteryValue = (try? c.decodeIfPresent(BatteryValue.self, forKey: .batteryValue)) ?? d.batteryValue
        sensorUnit = (try? c.decodeIfPresent(TemperatureUnit.self, forKey: .sensorUnit)) ?? d.sensorUnit
    }

    /// Whether `kind` is counted (empty selection = all).
    func includes(_ kind: AgentKind) -> Bool { agents.isEmpty || agents.contains(kind) }

    /// Modules that have options beyond the look.
    static func hasOptions(_ module: Module) -> Bool {
        [.agents, .memory, .network, .disk, .battery, .sensors].contains(module)
    }

    enum AgentValue: String, Codable, CaseIterable, Identifiable {
        case limitsLeft, limitsUsed, tokensToday, tokensWeek, tokensWindow
        var id: String { rawValue }
        var title: String {
            switch self {
            case .limitsLeft: "Limits: % left"
            case .limitsUsed: "Limits: % used"
            case .tokensToday: "Tokens today"
            case .tokensWeek: "Tokens this week"
            case .tokensWindow: "Tokens this 5-hour window"
            }
        }
        var isLimits: Bool { self == .limitsLeft || self == .limitsUsed }
    }

    enum AgentWindows: String, Codable, CaseIterable, Identifiable {
        case both, session, longest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .both: "Session and weekly"
            case .session: "Current session only"
            case .longest: "Weekly (or monthly) only"
            }
        }
    }

    enum MemoryValue: String, Codable, CaseIterable, Identifiable {
        case percent, used, free
        var id: String { rawValue }
        var title: String {
            switch self {
            case .percent: "Percent used"
            case .used: "Amount used"
            case .free: "Amount free"
            }
        }
    }

    enum Directions: String, Codable, CaseIterable, Identifiable {
        case both, download, upload
        var id: String { rawValue }
        var title: String {
            switch self {
            case .both: "Upload and download"
            case .download: "Download only"
            case .upload: "Upload only"
            }
        }
    }

    enum DiskValue: String, Codable, CaseIterable, Identifiable {
        case rates, free
        var id: String { rawValue }
        var title: String { self == .rates ? "Read and write rates" : "Startup disk free space" }
    }

    enum BatteryValue: String, Codable, CaseIterable, Identifiable {
        case percent, time, both
        var id: String { rawValue }
        var title: String {
            switch self {
            case .percent: "Percent"
            case .time: "Time remaining"
            case .both: "Percent and time"
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
    /// them (Claude Code first); Claude Code without live limits falls back to its local 5-hour estimate;
    /// otherwise tokens.
    func menuBarContent(_ options: ItemOptions) -> AgentMenuContent {
        let counted = agents(for: options)
        if options.agentValue.isLimits {
            if let withLimits = counted.first(where: { !$0.limits.isEmpty }) {
                var windows = withLimits.limits.sorted { $0.windowMinutes < $1.windowMinutes }
                switch options.agentWindows {
                case .both: windows = Array(windows.prefix(2))
                case .session: windows = Array(windows.prefix(1))
                case .longest: windows = Array(windows.suffix(1))
                }
                return .limits(windows, used: options.agentValue == .limitsUsed)
            }
            if let claude = counted.first(where: { $0.agent == .claude }), let block = claude.block {
                return .claudeEstimate(block, today: claude.today.total)
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

/// What the agents menu bar item draws.
enum AgentMenuContent: Equatable {
    case limits([RateWindow], used: Bool)
    case claudeEstimate(UsageBlock, today: Int)
    case tokens(Int)
}
