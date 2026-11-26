import AppIntents
import Foundation

/// What the active Focus asks of VibeCheck. Set by `VibeCheckFocusFilter.perform()`.
struct FocusFilterState: Equatable, Sendable, Codable {
    var holdAlerts = false
    var keepDisplayAwake = false
    var pauseMeetingAlerts = false
    var pauseHourlyChime = false
    static let inactive = FocusFilterState()

    init(holdAlerts: Bool = false, keepDisplayAwake: Bool = false,
         pauseMeetingAlerts: Bool = false, pauseHourlyChime: Bool = false) {
        self.holdAlerts = holdAlerts
        self.keepDisplayAwake = keepDisplayAwake
        self.pauseMeetingAlerts = pauseMeetingAlerts
        self.pauseHourlyChime = pauseHourlyChime
    }

    /// Backward-compatible decode so saved Focus states from earlier versions keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        holdAlerts = try c.decodeIfPresent(Bool.self, forKey: .holdAlerts) ?? false
        keepDisplayAwake = try c.decodeIfPresent(Bool.self, forKey: .keepDisplayAwake) ?? false
        pauseMeetingAlerts = try c.decodeIfPresent(Bool.self, forKey: .pauseMeetingAlerts) ?? false
        pauseHourlyChime = try c.decodeIfPresent(Bool.self, forKey: .pauseHourlyChime) ?? false
    }

    /// Hold non-critical alerts while a call is on or the Focus asks for it.
    nonisolated static func holdAlerts(inCall: Bool, focus: FocusFilterState) -> Bool { inCall || focus.holdAlerts }

    /// Whether the Focus asks to keep the display awake.
    nonisolated static func keepAwakeActive(focus: FocusFilterState) -> Bool { focus.keepDisplayAwake }

    /// Whether meeting alerts (fullscreen / banner) should pause during this Focus.
    nonisolated static func suppressMeetingAlerts(focus: FocusFilterState) -> Bool { focus.pauseMeetingAlerts }

    /// Whether the hourly chime should silence during this Focus.
    nonisolated static func suppressHourlyChime(focus: FocusFilterState) -> Bool { focus.pauseHourlyChime }
}

/// Shared Focus state, applied by the app on the main actor.
@MainActor
final class FocusFilterStore {
    static let shared = FocusFilterStore()
    /// Kept across launches: the system only calls `perform()` when the Focus changes, so a relaunch during a
    /// Focus would otherwise forget it. Per Mac, not in settings backup.
    private static let key = "focusFilterState"
    private(set) var state: FocusFilterState

    init() {
        state = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(FocusFilterState.self, from: $0) } ?? .inactive
    }

    func apply(_ new: FocusFilterState) {
        guard new != state else { return }
        state = new
        if let data = try? JSONEncoder().encode(new) { UserDefaults.standard.set(data, forKey: Self.key) }
        NSLog("%@", "VibeCheck focus filter: hold alerts \(new.holdAlerts), keep awake \(new.keepDisplayAwake), pause meetings \(new.pauseMeetingAlerts), pause chime \(new.pauseHourlyChime)")
        KeepAwake.shared.check()
    }
}

/// A Focus filter (System Settings > Focus > Add Filter > VibeCheck). When the Focus turns off the system calls
/// `perform()` again with the default values, so all switches default to off.
struct VibeCheckFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "VibeCheck"
    static let description: IntentDescription? = IntentDescription("Hold alerts, keep the display awake, or pause meeting alerts and hourly chime while this Focus is on.")

    @Parameter(title: "Hold alerts", description: "Hold non-critical alerts until this Focus ends.", default: false)
    var holdAlerts: Bool

    @Parameter(title: "Keep display awake", description: "Keep the display awake while this Focus is on.", default: false)
    var keepDisplayAwake: Bool

    @Parameter(title: "Pause meeting alerts", description: "Pause fullscreen and banner meeting notifications while this Focus is on.", default: false)
    var pauseMeetingAlerts: Bool

    @Parameter(title: "Pause hourly chime", description: "Mute the hourly chime while this Focus is on.", default: false)
    var pauseHourlyChime: Bool

    var displayRepresentation: DisplayRepresentation {
        var parts: [String] = []
        if holdAlerts { parts.append(String(localized: "Hold alerts")) }
        if keepDisplayAwake { parts.append(String(localized: "keep display awake")) }
        if pauseMeetingAlerts { parts.append(String(localized: "pause meetings")) }
        if pauseHourlyChime { parts.append(String(localized: "pause chime")) }
        let subtitle: LocalizedStringResource = parts.isEmpty ? "No changes" : "\(parts.joined(separator: ", "))"
        return DisplayRepresentation(title: "VibeCheck", subtitle: subtitle)
    }

    func perform() async throws -> some IntentResult {
        let state = FocusFilterState(holdAlerts: holdAlerts, keepDisplayAwake: keepDisplayAwake,
                                     pauseMeetingAlerts: pauseMeetingAlerts, pauseHourlyChime: pauseHourlyChime)
        await MainActor.run { FocusFilterStore.shared.apply(state) }
        return .result()
    }
}
