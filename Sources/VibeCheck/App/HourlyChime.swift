import AppKit
import Foundation

/// How often the optional clock chime plays during active hours.
enum ChimeCadence: String, CaseIterable, Identifiable, Codable, Sendable {
    case hourly, halfHourly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hourly: String(localized: "Every hour")
        case .halfHourly: String(localized: "Every 30 minutes")
        }
    }
}

/// Built-in macOS system sounds suitable for a subtle hourly chime (zero extra bundle assets).
enum ChimeSound: String, CaseIterable, Identifiable, Codable, Sendable {
    case tink = "Tink"
    case glass = "Glass"
    case pop = "Pop"
    case purr = "Purr"
    case ping = "Ping"
    case hero = "Hero"
    case morse = "Morse"
    case submarine = "Submarine"

    var id: String { rawValue }
    var title: String { rawValue }
}

/// Pure scheduling and active-hours rules for the hourly chime (unit-tested).
enum HourlyChimeLogic {
    /// Next `:00` (or `:00` / `:30`) boundary strictly after `now`.
    nonisolated static func nextFireDate(after now: Date,
                                         cadence: ChimeCadence,
                                         calendar: Calendar = .current) -> Date {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let currentMinute = comps.minute ?? 0
        var base = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day,
                                                      hour: comps.hour, minute: 0, second: 0)) ?? now
        let targetMinutes: Int
        switch cadence {
        case .hourly:
            targetMinutes = 60
        case .halfHourly:
            targetMinutes = currentMinute < 30 ? 30 : 60
        }
        base = base.addingTimeInterval(TimeInterval(targetMinutes * 60))
        // Guard against firing twice in the same boundary second.
        if base.timeIntervalSince(now) < 1 {
            base = base.addingTimeInterval(TimeInterval((cadence == .hourly ? 60 : 30) * 60))
        }
        return base
    }

    /// True if the chime should play at `date`, respecting active hours, active calls, Focus, and screen lock.
    nonisolated static func shouldChime(at date: Date,
                                        enabled: Bool,
                                        startMinute: Int,
                                        endMinute: Int,
                                        inCall: Bool,
                                        focusPaused: Bool,
                                        screenLocked: Bool,
                                        calendar: Calendar = .current) -> Bool {
        guard enabled, !inCall, !focusPaused, !screenLocked else { return false }
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let nowMinutes = hour * 60 + minute
        if startMinute == endMinute { return true }
        if startMinute < endMinute {
            return nowMinutes >= startMinute && nowMinutes <= endMinute
        } else {
            // Overnight window (e.g. 20:00 – 06:00).
            return nowMinutes >= startMinute || nowMinutes <= endMinute
        }
    }
}

/// Plays a subtle system chime on the hour (or half-hour) during active hours.
/// Uses a single next-boundary timer (zero polling) and auto-silences during calls or Focus.
@MainActor
final class HourlyChimeManager {
    static let shared = HourlyChimeManager()

    private var timer: Timer?
    private var observer: NSObjectProtocol?

    private init() {}

    func start() {
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .vibeCheckSettingsChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reschedule() }
            }
        }
        reschedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func reschedule() {
        timer?.invalidate()
        timer = nil
        let clock = AppSettings.shared.clock
        guard clock.hourlyChimeEnabled else { return }
        let next = HourlyChimeLogic.nextFireDate(after: Date(), cadence: clock.hourlyChimeCadence)
        let delay = max(1, next.timeIntervalSinceNow)
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fire()
                self?.reschedule()
            }
        }
        t.tolerance = 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func preview(sound: ChimeSound, volume: Double) {
        play(sound: sound, volume: volume)
    }

    private func fire() {
        let clock = AppSettings.shared.clock
        let ok = HourlyChimeLogic.shouldChime(
            at: Date(),
            enabled: clock.hourlyChimeEnabled,
            startMinute: clock.hourlyChimeStartMinute,
            endMinute: clock.hourlyChimeEndMinute,
            inCall: CallGuard.shared.inCall,
            focusPaused: FocusFilterState.suppressHourlyChime(focus: FocusFilterStore.shared.state),
            screenLocked: MeetingAlertPolicy.isScreenLocked()
        )
        guard ok else { return }
        play(sound: clock.hourlyChimeSound, volume: clock.hourlyChimeVolume)
    }

    private func play(sound: ChimeSound, volume: Double) {
        guard let ns = NSSound(named: NSSound.Name(sound.rawValue)) else { return }
        ns.volume = Float(min(max(volume, 0.05), 1.0))
        ns.play()
    }
}
