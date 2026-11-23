import Foundation

/// The machine-readable status the app writes to `~/Library/Application Support/VibeCheck/status.json`
/// and the bundled `vibecheck` command line tool reads. Foundation only, so the CLI stays tiny.
///
/// Schema version 1 (field names are a public contract; add fields, never rename):
/// - `schema`: 1
/// - `updatedAt`: ISO 8601 time of the write
/// - `pid`: the writing app's process id (lets the CLI tell a quit app from a live one)
/// - `vibe`: "vibing" | "mid" | "cooked"
/// - `verdict`: the app's one-sentence verdict (localized)
/// - `culprit`: the module behind the verdict ("memory", "cpu", ...), nil while vibing
/// - `cpu`: 0...1, average over the last 30 s
/// - `memoryPressure`: "normal" | "warning" | "critical"
/// - `swapUsedBytes`
/// - `thermalState`: "nominal" | "fair" | "serious" | "critical"
/// - `battery`: { percent (0...1), onAC, minutesLeft? }, nil on desktops
/// - `topMemory`: up to 5 apps { name, bytes, processes, growthBytes?, growthMinutes? }
/// - `limits`: optional, [{ agent, name, usedPercent, resetsAt, runsOutAt? }] with the run-out forecast at the
///   average pace since the window started; omitted when no agent reports limits
/// - `energyToday`: optional, up to 5 apps { name, wattHours, share (0...1) } by energy used since midnight
///   (estimated by macOS per process, on battery or plugged in); omitted until something has been counted
/// - `topCPU` / `topCPUAt`: up to 5 apps { name, cpu (percent of one core), processes } and when they were
///   read; present only while the deck (or another view) has process sampling on, otherwise omitted
public struct StatusSnapshot: Codable, Equatable, Sendable {
    public static let currentSchema = 1

    public struct Battery: Codable, Equatable, Sendable {
        public var percent: Double
        public var onAC: Bool
        public var minutesLeft: Int?
        public init(percent: Double, onAC: Bool, minutesLeft: Int? = nil) {
            self.percent = percent; self.onAC = onAC; self.minutesLeft = minutesLeft
        }
    }

    public struct MemoryApp: Codable, Equatable, Sendable {
        public var name: String
        public var bytes: Double
        public var processes: Int
        public var growthBytes: Double?
        public var growthMinutes: Int?
        public init(name: String, bytes: Double, processes: Int, growthBytes: Double? = nil, growthMinutes: Int? = nil) {
            self.name = name; self.bytes = bytes; self.processes = processes
            self.growthBytes = growthBytes; self.growthMinutes = growthMinutes
        }
    }

    public struct CPUApp: Codable, Equatable, Sendable {
        public var name: String
        public var cpu: Double
        public var processes: Int
        public init(name: String, cpu: Double, processes: Int) {
            self.name = name; self.cpu = cpu; self.processes = processes
        }
    }

    /// One provider limit with its forecast (`runsOutAt` is nil when it would last until `resetsAt`).
    public struct Limit: Codable, Equatable, Sendable {
        public var agent: String
        public var name: String
        public var usedPercent: Double
        public var resetsAt: Date
        public var runsOutAt: Date?
        public init(agent: String, name: String, usedPercent: Double, resetsAt: Date, runsOutAt: Date? = nil) {
            self.agent = agent; self.name = name; self.usedPercent = usedPercent
            self.resetsAt = resetsAt; self.runsOutAt = runsOutAt
        }
    }

    /// One app's estimated energy since local midnight.
    public struct EnergyApp: Codable, Equatable, Sendable {
        public var name: String
        public var wattHours: Double
        public var share: Double
        public init(name: String, wattHours: Double, share: Double) {
            self.name = name; self.wattHours = wattHours; self.share = share
        }
    }

    public var schema: Int
    public var updatedAt: Date
    public var pid: Int32?
    public var vibe: String
    public var verdict: String
    public var culprit: String?
    public var cpu: Double
    public var memoryPressure: String
    public var swapUsedBytes: Double
    public var thermalState: String
    public var battery: Battery?
    public var topMemory: [MemoryApp]
    public var topCPU: [CPUApp]?
    public var topCPUAt: Date?
    /// Provider limits (from agent logs) with the run-out forecast; omitted when none are known.
    public var limits: [Limit]?
    /// Top apps by energy used today; omitted when nothing has been counted yet.
    public var energyToday: [EnergyApp]?

    public init(schema: Int = StatusSnapshot.currentSchema, updatedAt: Date, pid: Int32? = nil, vibe: String, verdict: String,
                culprit: String? = nil, cpu: Double, memoryPressure: String, swapUsedBytes: Double,
                thermalState: String, battery: Battery? = nil, topMemory: [MemoryApp] = [],
                topCPU: [CPUApp]? = nil, topCPUAt: Date? = nil, limits: [Limit]? = nil,
                energyToday: [EnergyApp]? = nil) {
        self.schema = schema; self.updatedAt = updatedAt; self.pid = pid; self.vibe = vibe; self.verdict = verdict
        self.culprit = culprit; self.cpu = cpu; self.memoryPressure = memoryPressure
        self.swapUsedBytes = swapUsedBytes; self.thermalState = thermalState; self.battery = battery
        self.topMemory = topMemory; self.topCPU = topCPU; self.topCPUAt = topCPUAt; self.limits = limits
        self.energyToday = energyToday
    }

    // MARK: Coding

    public static func makeEncoder(pretty: Bool = true) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted] : [.sortedKeys]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func encoded(pretty: Bool = true) throws -> Data { try Self.makeEncoder(pretty: pretty).encode(self) }
    public static func decode(_ data: Data) throws -> StatusSnapshot { try makeDecoder().decode(StatusSnapshot.self, from: data) }

    /// Where the app writes the file (the app is not sandboxed, so this is the real Application Support folder).
    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("VibeCheck/status.json")
    }

    // MARK: Change detection (the publisher's rules, pure)

    public static let minWriteInterval: TimeInterval = 10
    public static let heartbeat: TimeInterval = 300
    public static let cpuDelta = 0.05

    /// Differences worth a write: vibe, verdict, culprit, memory pressure, thermal state, charger plugged in or
    /// not, the names of the top memory apps, or CPU moving 5 points or more.
    public func differsMeaningfully(from old: StatusSnapshot) -> Bool {
        vibe != old.vibe || verdict != old.verdict || culprit != old.culprit
            || memoryPressure != old.memoryPressure || thermalState != old.thermalState
            || battery?.onAC != old.battery?.onAC
            || topMemory.map(\.name) != old.topMemory.map(\.name)
            || abs(cpu - old.cpu) >= Self.cpuDelta
    }

    /// Whether to write `new` now. Never more than once per 10 s; otherwise on a meaningful change or a 5 min heartbeat.
    public static func shouldWrite(new: StatusSnapshot, last: StatusSnapshot?, lastWrite: Date?, now: Date) -> Bool {
        guard let last, let lastWrite else { return true }
        let since = now.timeIntervalSince(lastWrite)
        if since < minWriteInterval { return false }
        return since >= heartbeat || new.differsMeaningfully(from: last)
    }

    // MARK: Reading (CLI)

    public enum LoadResult: Equatable, Sendable {
        case snapshot(StatusSnapshot)
        /// No file: the app has never run (or was removed).
        case missing
        /// Empty, malformed or not a snapshot this tool understands.
        case unreadable
    }

    /// `nil` data means no file. A newer schema still loads when it decodes (fields are only ever added).
    public static func load(_ data: Data?) -> LoadResult {
        guard let data else { return .missing }
        guard !data.isEmpty, let snapshot = try? decode(data) else { return .unreadable }
        return .snapshot(snapshot)
    }

    public func notRunningMessage() -> String {
        "VibeCheck isn't running (last update \(updatedAt.formatted(.iso8601)))."
    }

    public static let staleAfter: TimeInterval = 600
    public static let cpuFreshFor: TimeInterval = 120

    /// Old news: not updated for 10 min, or the writing app is gone (`isAlive` answers for `pid`).
    public func isStale(now: Date = Date(), isAlive: (Int32) -> Bool = { _ in true }) -> Bool {
        if now.timeIntervalSince(updatedAt) > Self.staleAfter { return true }
        if let pid, !isAlive(pid) { return true }
        return false
    }

    /// Process CPU rows, only when they were read under 2 minutes ago.
    public func freshTopCPU(now: Date = Date()) -> [CPUApp]? {
        guard let rows = topCPU, !rows.isEmpty, let at = topCPUAt, now.timeIntervalSince(at) < Self.cpuFreshFor else { return nil }
        return rows
    }

    /// 0 vibing, 1 mid, 2 cooked (anything unknown counts as vibing).
    public var moodExitCode: Int32 {
        switch vibe { case "mid": 1; case "cooked": 2; default: 0 }
    }

    /// The JSON the CLI prints: sorted keys, plus `"stale": true` when stale.
    public func cliJSON(stale: Bool) throws -> Data {
        let data = try encoded()
        guard stale, var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
        object["stale"] = true
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
    }

    // MARK: Text

    public static func bytesText(_ value: Double) -> String {
        let gb = value / 1_000_000_000
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", value / 1_000_000)
    }

    /// "Mid: memory is getting tight. Chrome grew 2.4 GB in the last hour." Vibing keeps the app's sentence.
    public func humanStatus(stale: Bool = false) -> String {
        var line = verdict
        if vibe != "vibing", let colon = verdict.range(of: ": ") {
            line = vibe.prefix(1).uppercased() + vibe.dropFirst() + ": " + verdict[colon.upperBound...]
        }
        return stale ? line + " (stale: last update \(updatedAt.formatted(.iso8601)))" : line
    }

    /// Rows for `culprits`, one per line: "1. Chrome  2.4 GB (12 processes)".
    public func culpritLines(by: String, top: Int, now: Date = Date()) -> (lines: [String], usedCPU: Bool) {
        let limit = max(1, min(top, 5))
        if by == "cpu", let rows = freshTopCPU(now: now) {
            return (rows.prefix(limit).enumerated().map { i, r in
                "\(i + 1). \(r.name)  \(Int(r.cpu.rounded()))% CPU" + (r.processes > 1 ? " (\(r.processes) processes)" : "")
            }, true)
        }
        return (topMemory.prefix(limit).enumerated().map { i, m in
            var s = "\(i + 1). \(m.name)  \(Self.bytesText(m.bytes))" + (m.processes > 1 ? " (\(m.processes) processes)" : "")
            if let g = m.growthBytes, g >= 100_000_000, let mins = m.growthMinutes { s += ", +\(Self.bytesText(g)) in \(mins) min" }
            return s
        }, false)
    }
}
