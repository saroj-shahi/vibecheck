import Foundation

/// Why the sampling tick is paused: nobody can see the menu bar or the deck.
enum TickSuspendReason: Hashable, CaseIterable {
    case displayAsleep, sessionInactive, screenLocked
}

/// Decides how often the tick runs from the pause reasons, Low Power Mode and keep-awake. Pure, so it's testable.
enum TickPolicy {
    /// While paused with a keep-awake session running, still check its end condition this often.
    static let keepAwakeInterval: TimeInterval = 30
    static let lowPowerMinimum: TimeInterval = 4

    /// Seconds between ticks, or nil when the tick should stop completely.
    nonisolated static func interval(base: TimeInterval, reasons: Set<TickSuspendReason>,
                                     lowPower: Bool, keepAwakeSession: Bool) -> TimeInterval? {
        let normal = lowPower ? max(base * 2, lowPowerMinimum) : base
        guard !reasons.isEmpty else { return normal }
        return keepAwakeSession ? max(normal, keepAwakeInterval) : nil
    }
}

extension Notification.Name {
    /// The tick paused or resumed; animations that only matter on screen follow it.
    static let vibeCheckTickSuspendedChanged = Notification.Name("VibeCheckTickSuspendedChanged")
}

/// Main-actor flag mirroring "the tick is paused", for views with their own timers.
@MainActor
enum TickGate {
    private(set) static var isSuspended = false
    static func set(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        NotificationCenter.default.post(name: .vibeCheckTickSuspendedChanged, object: nil)
    }
}
