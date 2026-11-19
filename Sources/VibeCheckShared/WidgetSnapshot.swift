import Foundation

/// What the app hands the widgets: the vibe and the last hour of CPU and memory, written as JSON into the
/// shared app group container. The widget extension is sandboxed and can only read that container.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// 0 vibing, 1 mid, 2 cooked (the app's `Vibe` raw values).
    public var vibe: Int
    /// The vibe word ("Vibing", "Mid", "Cooked") and the reason, localized by the app.
    public var vibeTitle: String
    public var verdict: String
    /// Readings now, 0...1.
    public var cpu: Double
    public var memory: Double
    /// Last hour, oldest first, 0...1, at most `maxPoints` each.
    public var cpuHour: [Double]
    public var memoryHour: [Double]
    public var date: Date

    public static let maxPoints = 60

    public init(vibe: Int, vibeTitle: String, verdict: String, cpu: Double, memory: Double,
                cpuHour: [Double], memoryHour: [Double], date: Date) {
        self.vibe = vibe
        self.vibeTitle = vibeTitle
        self.verdict = verdict
        self.cpu = cpu
        self.memory = memory
        self.cpuHour = cpuHour
        self.memoryHour = memoryHour
        self.date = date
    }

    /// Shown in the widget gallery and before the app has written anything.
    public static let placeholder = WidgetSnapshot(
        vibe: 0, vibeTitle: "Vibing", verdict: "Your Mac is vibing", cpu: 0.18, memory: 0.52,
        cpuHour: (0..<maxPoints).map { 0.15 + 0.1 * sin(Double($0) / 5) + ($0 % 7 == 0 ? 0.15 : 0) },
        memoryHour: (0..<maxPoints).map { 0.5 + 0.03 * sin(Double($0) / 9) },
        date: Date(timeIntervalSince1970: 0))

    /// Averages `values` down to at most `count` points, keeping order (newest last).
    public static func downsample(_ values: [Double], to count: Int = maxPoints) -> [Double] {
        guard values.count > count, count > 0 else { return values }
        let size = Double(values.count) / Double(count)
        return (0..<count).map { i in
            let slice = values[Int(Double(i) * size)..<max(Int(Double(i) * size) + 1, Int(Double(i + 1) * size))]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    /// The snapshot is old news after this long without an update (app quit or Mac asleep).
    public func isStale(at now: Date) -> Bool { now.timeIntervalSince(date) > Self.staleAfter }
    public static let staleAfter: TimeInterval = 15 * 60
}

public enum WidgetShared {
    /// Team-prefixed app group: works on macOS without a provisioning profile.
    public static let appGroup = "77HKFF78Z8.local.vibecheck"
    public static let ringKind = "VibeRingWidget"
    public static let sparklineKind = "SparklineWidget"

    public static var snapshotURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget-snapshot.json")
    }

    public static func read(from url: URL? = snapshotURL) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    public static func write(_ snapshot: WidgetSnapshot, to url: URL? = snapshotURL) -> Bool {
        guard let url else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
