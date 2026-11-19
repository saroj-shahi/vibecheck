import Foundation
import UserNotifications

enum AlertMetric: String, Codable, CaseIterable, Identifiable {
    case cpu, gpu, memory, temperature, batteryLevel, diskFree, agentTokens, accessoryBattery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU usage"
        case .gpu: "GPU usage"
        case .memory: "Memory usage"
        case .temperature: "Temperature"
        case .batteryLevel: "Battery level"
        case .diskFree: "Startup disk free space"
        case .agentTokens: "Agent tokens per hour"
        case .accessoryBattery: "Accessory battery"
        }
    }

    var unit: String {
        switch self {
        case .temperature: "°C"
        case .agentTokens: "M"   // millions of tokens in the last 60 minutes
        default: "%"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .temperature: 30...110
        case .agentTokens: 1...500
        default: 1...100
        }
    }

    /// The module whose Settings page lists alerts on this metric.
    var module: Module {
        switch self {
        case .cpu: .cpu
        case .gpu: .gpu
        case .memory: .memory
        case .temperature: .sensors
        case .batteryLevel, .accessoryBattery: .battery
        case .diskFree: .disk
        case .agentTokens: .agents
        }
    }

    /// Levels that run out are watched from below ("battery below 15%"); load is watched from above.
    var defaultComparison: AlertComparison {
        [.batteryLevel, .diskFree, .accessoryBattery].contains(self) ? .below : .above
    }

    /// Metrics that can be alerted on for a module, in menu order.
    static func metrics(for module: Module) -> [AlertMetric] { allCases.filter { $0.module == module } }
}

enum AlertComparison: String, Codable, CaseIterable, Identifiable {
    case above, below
    var id: String { rawValue }
}

struct AlertRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var enabled = true
    var metric: AlertMetric
    var comparison: AlertComparison
    var threshold: Double
    var duration: TimeInterval   // condition must hold this long before notifying

    static let durations: [(TimeInterval, String)] =
        [(0, "instantly"), (10, "10 sec"), (30, "30 sec"), (60, "1 min"), (300, "5 min"), (900, "15 min")]

    /// A new alert for `metric`: the default rule's numbers when there is one, otherwise a sensible start.
    static func starter(for metric: AlertMetric) -> AlertRule {
        if let rule = defaults.first(where: { $0.metric == metric }) { return AlertRule(metric: metric, comparison: rule.comparison, threshold: rule.threshold, duration: rule.duration) }
        let threshold: Double = switch metric {
        case .agentTokens: 50
        case .accessoryBattery: 20
        default: 80
        }
        return AlertRule(metric: metric, comparison: metric.defaultComparison, threshold: threshold,
                         duration: metric.defaultComparison == .below ? 0 : 60)
    }

    static func durationLabel(_ seconds: TimeInterval) -> String {
        durations.first { $0.0 == seconds }?.1 ?? "\(Int(seconds)) sec"
    }

    static let defaults: [AlertRule] = [
        AlertRule(metric: .cpu, comparison: .above, threshold: 90, duration: 60),
        AlertRule(metric: .temperature, comparison: .above, threshold: 95, duration: 30),
        AlertRule(metric: .memory, comparison: .above, threshold: 90, duration: 60),
        AlertRule(metric: .batteryLevel, comparison: .below, threshold: 15, duration: 0),
        AlertRule(metric: .diskFree, comparison: .below, threshold: 10, duration: 0),
    ]

    /// `detail` names what the reading belongs to (e.g. the accessory), giving "MX Keys is at 18%." instead of "Now 18%.".
    func describe(current: Double, detail: String? = nil) -> String {
        let when = duration > 0 ? " for \(Self.durationLabel(duration))" : ""
        let reading = "\(Int(current.rounded()))\(metric.unit)"
        return "\(metric.title) has been \(comparison.rawValue) \(Int(threshold))\(metric.unit)\(when). "
            + (detail.map { "\($0) is at \(reading)." } ?? "Now \(reading).")
    }
}

/// Checks every enabled rule each tick and posts a notification when one has held long enough.
/// A rule fires once, then re-arms after the condition clears (with a cooldown to avoid flapping).
@MainActor
final class AlertEngine: NSObject, UNUserNotificationCenterDelegate {
    private var conditionSince: [UUID: Date] = [:]
    private var fired: Set<UUID> = []
    private var lastFired: [UUID: Date] = [:]
    private var askedPermission = false
    private let cooldown: TimeInterval = 300
    /// Notifications need a real app bundle; the debug binary and tests just log instead.
    private let canNotify = Bundle.main.bundleIdentifier != nil
    /// Where alerts go; replaceable for tests.
    var deliver: ((_ title: String, _ body: String) -> Void)?
    /// Where sent notifications are kept for the deck's history (nil = not kept, e.g. in tests).
    var log: NotificationLog?

    override init() {
        super.init()
        if canNotify { UNUserNotificationCenter.current().delegate = self }
    }

    static func value(for metric: AlertMetric, in stats: SystemStats) -> Double? {
        switch metric {
        case .cpu: stats.cpu.total * 100
        case .gpu: stats.gpu.gpus.isEmpty ? nil : stats.gpu.utilization * 100
        case .memory: stats.memory.usage * 100
        case .temperature: stats.sensors.hottest
        case .batteryLevel: stats.battery.present ? stats.battery.percent * 100 : nil
        case .diskFree:
            (stats.volumes.first { $0.path == "/" } ?? stats.volumes.first).map { (1 - $0.usage) * 100 }
        case .agentTokens:
            agentTokensPerHour(AgentUsageStore.shared.sample, enabled: AppSettings.shared.isEnabled(.agents))
        case .accessoryBattery: lowestAccessory(in: stats.devices).map { Double($0.percent) }
        }
    }

    /// The connected accessory with the lowest battery; devices that report no level are ignored.
    nonisolated static func lowestAccessory(in devices: [DeviceBattery]) -> (name: String, percent: Int)? {
        devices.compactMap { device in device.lowest.map { (name: device.name, percent: $0) } }
            .min { $0.percent < $1.percent }
    }

    /// Millions of tokens in the last 60 minutes, across all agents; nil until the first scan or with Agents off.
    nonisolated static func agentTokensPerHour(_ sample: AgentUsageSample, enabled: Bool) -> Double? {
        guard enabled, sample.scanned, !sample.agents.isEmpty else { return nil }
        return Double(sample.lastHour) / 1_000_000
    }

    func evaluate(_ rules: [AlertRule], stats: SystemStats, now: Date = Date()) {
        evaluate(rules, now: now, detail: { $0 == .accessoryBattery ? Self.lowestAccessory(in: stats.devices)?.name : nil },
                 value: { Self.value(for: $0, in: stats) })
    }

    /// `detail` optionally names the source of a metric's reading (the accessory) for the notification text.
    func evaluate(_ rules: [AlertRule], now: Date = Date(), detail: (AlertMetric) -> String? = { _ in nil },
                  value valueFor: (AlertMetric) -> Double?) {
        let active = rules.filter(\.enabled)
        if !active.isEmpty { requestPermissionIfNeeded() }

        for rule in active {
            guard let value = valueFor(rule.metric) else { continue }
            let tripped = rule.comparison == .above ? value > rule.threshold : value < rule.threshold
            guard tripped else {
                conditionSince[rule.id] = nil
                fired.remove(rule.id)
                continue
            }
            let since = conditionSince[rule.id] ?? now
            conditionSince[rule.id] = since
            let cooledDown = lastFired[rule.id].map { now.timeIntervalSince($0) > cooldown } ?? true
            if !fired.contains(rule.id), cooledDown, now.timeIntervalSince(since) >= rule.duration {
                fired.insert(rule.id)
                lastFired[rule.id] = now
                let title = "VibeCheck · \(rule.metric.title)", body = rule.describe(current: value, detail: detail(rule.metric))
                post(title: title, body: body)
                log?.record(.alert, title: title, body: body, at: now)
            }
        }
        // Forget state for rules that were deleted or disabled.
        let ids = Set(active.map(\.id))
        conditionSince = conditionSince.filter { ids.contains($0.key) }
        fired.formIntersection(ids)
    }

    /// A one-off notification from elsewhere in the app (e.g. keep awake ending).
    func notify(title: String, body: String, kind: LoggedNotification.Kind) {
        requestPermissionIfNeeded()
        post(title: title, body: body)
        log?.record(kind, title: title, body: body)
    }

    func sendTest() {
        requestPermissionIfNeeded()
        post(title: "VibeCheck", body: "Notifications are working. Your Mac's vibes are being watched. 👀")
    }

    private func requestPermissionIfNeeded() {
        guard canNotify, !askedPermission else { return }
        askedPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if !granted { NSLog("VibeCheck: notifications not allowed \(error?.localizedDescription ?? "")") }
        }
    }

    private func post(title: String, body: String) {
        if let deliver { deliver(title, body); return }
        guard canNotify else { NSLog("VibeCheck alert: \(title): \(body)"); return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Show banners even while the menu bar app counts as "active".
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
