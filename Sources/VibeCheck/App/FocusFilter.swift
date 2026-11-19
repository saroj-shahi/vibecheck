import AppIntents
import Foundation

/// What the active Focus asks of VibeCheck. Set by `VibeCheckFocusFilter.perform()`.
struct FocusFilterState: Equatable, Sendable, Codable {
    var holdAlerts = false
    var keepDisplayAwake = false
    static let inactive = FocusFilterState()

    /// Hold non-critical alerts while a call is on or the Focus asks for it.
    nonisolated static func holdAlerts(inCall: Bool, focus: FocusFilterState) -> Bool { inCall || focus.holdAlerts }

    /// Whether the Focus asks to keep the display awake.
    nonisolated static func keepAwakeActive(focus: FocusFilterState) -> Bool { focus.keepDisplayAwake }
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
        NSLog("%@", "VibeCheck focus filter: hold alerts \(new.holdAlerts), keep awake \(new.keepDisplayAwake)")
        KeepAwake.shared.check()
    }
}

/// A Focus filter (System Settings > Focus > Add Filter > VibeCheck). When the Focus turns off the system calls
/// `perform()` again with the default values, so both switches default to off.
struct VibeCheckFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "VibeCheck"
    static let description: IntentDescription? = IntentDescription("Hold alerts or keep the display awake while this Focus is on.")

    @Parameter(title: "Hold alerts", description: "Hold non-critical alerts until this Focus ends.", default: false)
    var holdAlerts: Bool

    @Parameter(title: "Keep display awake", description: "Keep the display awake while this Focus is on.", default: false)
    var keepDisplayAwake: Bool

    var displayRepresentation: DisplayRepresentation {
        let subtitle: LocalizedStringResource = switch (holdAlerts, keepDisplayAwake) {
        case (true, true): "Hold alerts, keep display awake"
        case (true, false): "Hold alerts"
        case (false, true): "Keep display awake"
        case (false, false): "No changes"
        }
        return DisplayRepresentation(title: "VibeCheck", subtitle: subtitle)
    }

    func perform() async throws -> some IntentResult {
        let state = FocusFilterState(holdAlerts: holdAlerts, keepDisplayAwake: keepDisplayAwake)
        await MainActor.run { FocusFilterStore.shared.apply(state) }
        return .result()
    }
}
