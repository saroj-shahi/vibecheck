import AppKit
import IOKit.pwr_mgt
import Observation

extension Notification.Name {
    /// A keep-awake session started or ended (the menu bar shows a cup while one runs).
    static let vibeCheckKeepAwakeChanged = Notification.Name("VibeCheckKeepAwakeChanged")
}

/// When a keep-awake session ends on its own.
enum AwakeEnd: Hashable {
    /// Until it's stopped by hand.
    case never
    /// At a fixed time (sessions started "for 30 minutes" store their end time).
    case at(Date)
    /// While an app keeps running.
    case whileRunning(bundleID: String, name: String)
    /// Started by a trigger (power adapter, external display); ends when the trigger goes away.
    case whileTriggered(String)
}

/// Why a session stopped by itself.
enum AwakeEndReason: Equatable {
    case timeUp, appQuit, lowBattery, triggerOff
    /// A focus session ran its full length.
    case focusDone

    var message: String {
        switch self {
        case .timeUp: "Time's up."
        case .appQuit: "The app it was waiting on quit."
        case .lowBattery: "The battery got low."
        case .triggerOff: "What started it is gone (unplugged, display disconnected, downloads done or schedule over)."
        case .focusDone: "Focus session done. Take a break."
        }
    }

    /// Worth a notification: the Mac will start sleeping again without the user doing anything.
    var notifies: Bool { self != .triggerOff }
}

struct AwakeSession: Equatable {
    var started: Date
    var end: AwakeEnd
    /// A focus session: a timed session that ends with a "take a break" notification.
    var focus = false

    /// Checks the session's end condition and the battery floor (0 = no floor). Plain function so it's testable.
    static func endReason(_ session: AwakeSession, now: Date, battery: BatterySample, batteryFloor: Int,
                          isRunning: (String) -> Bool) -> AwakeEndReason? {
        switch session.end {
        case .never, .whileTriggered: break
        case .at(let date): if now >= date { return session.focus ? .focusDone : .timeUp }
        case .whileRunning(let bundleID, _): if !isRunning(bundleID) { return .appQuit }
        }
        if batteryFloor > 0, battery.present, !battery.onAC, battery.percent * 100 < Double(batteryFloor) {
            return .lowBattery
        }
        return nil
    }

    /// "42 min left", "1 h 5 min left", "until Safari quits", "until you stop it".
    func remaining(now: Date) -> String {
        switch end {
        case .never: return "until you stop it"
        case .whileRunning(_, let name): return "until \(name) quits"
        case .whileTriggered(let description): return description
        case .at(let date):
            let minutes = max(0, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
            if minutes < 60 { return "\(max(minutes, 1)) min left" }
            let hours = minutes / 60, rest = minutes % 60
            return rest == 0 ? "\(hours) h left" : "\(hours) h \(rest) min left"
        }
    }
}

extension AwakeSession {
    /// Whole minutes left in a timed session, rounded up; nil when it has no end time.
    func minutesLeft(now: Date) -> Int? {
        guard case .at(let date) = end else { return nil }
        return max(0, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
    }
}

enum FocusPreset {
    static let minutes = [25, 50, 90]
}

/// Quick-start lengths offered in the deck menu and Settings (0 = indefinitely).
enum AwakePreset {
    static let minutes = [0, 15, 30, 60, 120, 300]

    static func title(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Indefinitely"
        case ..<60: "\(minutes) minutes"
        case 60: "1 hour"
        default: minutes % 60 == 0 ? "\(minutes / 60) hours" : "\(minutes) minutes"
        }
    }

    static func end(_ minutes: Int, from now: Date = Date()) -> AwakeEnd {
        minutes > 0 ? .at(now.addingTimeInterval(Double(minutes) * 60)) : .never
    }

    /// The next time the clock shows this time of day (minutes after midnight): later today, or tomorrow.
    static func nextOccurrence(ofMinute minuteOfDay: Int, after now: Date = Date(), calendar: Calendar = .current) -> Date {
        let parts = DateComponents(hour: minuteOfDay / 60 % 24, minute: minuteOfDay % 60)
        return calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) ?? now.addingTimeInterval(86400)
    }

    /// Whole hours to offer in the deck's "Until" menu: the next `count`, starting at least 15 minutes out.
    static func upcomingHours(after now: Date = Date(), count: Int = 6, calendar: Calendar = .current) -> [Date] {
        guard let first = calendar.nextDate(after: now.addingTimeInterval(15 * 60), matching: DateComponents(minute: 0),
                                            matchingPolicy: .nextTime) else { return [] }
        return (0..<count).compactMap { calendar.date(byAdding: .hour, value: $0, to: first) }
    }
}

/// A weekly window to stay awake in, like weekdays 9:00–17:00. A window whose end is before its start runs
/// past midnight and belongs to the day it starts on.
struct AwakeSchedule: Equatable {
    /// Calendar weekdays (1 = Sunday … 7 = Saturday) as bits: bit n set means weekday n is on.
    var days: Int
    var startMinute: Int   // minutes after midnight
    var endMinute: Int

    static let weekdays = (2...6).reduce(0) { $0 | 1 << $1 }   // Monday to Friday

    func includes(weekday: Int) -> Bool { days & (1 << weekday) != 0 }

    /// Whether `now` is inside the window. Pure apart from the calendar, for tests.
    func isActive(at now: Date, calendar: Calendar = .current) -> Bool {
        guard startMinute != endMinute else { return false }
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        guard let weekday = parts.weekday else { return false }
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if startMinute < endMinute {
            return includes(weekday: weekday) && minute >= startMinute && minute < endMinute
        }
        // Overnight: the evening part belongs to today, the early-morning part to yesterday.
        let yesterday = weekday == 1 ? 7 : weekday - 1
        return (includes(weekday: weekday) && minute >= startMinute)
            || (includes(weekday: yesterday) && minute < endMinute)
    }

    /// "within your schedule (until 17:00)", in the user's clock style.
    func description(now: Date = Date(), calendar: Calendar = .current) -> String {
        let end = AwakePreset.nextOccurrence(ofMinute: endMinute, after: now, calendar: calendar)
        return "within your schedule (until \(end.formatted(date: .omitted, time: .shortened)))"
    }
}

/// What the automatic triggers want right now. Edge-triggered so a manual Stop sticks until the
/// condition goes away and comes back.
enum AwakeTriggerAction: Equatable {
    case start(String), stop, none

    static func decide(active: String?, wasActive: Bool, session: AwakeSession?) -> AwakeTriggerAction {
        if let active { return !wasActive && session == nil ? .start(active) : .none }
        if case .whileTriggered = session?.end { return .stop }
        return .none
    }

    /// "while plugged in", "while a display is connected", "while files are downloading", "while within your
    /// schedule (until …)", or several;
    /// nil when no trigger is on and met.
    static func description(onPower: Bool, externalDisplay: Bool, downloading: Bool = false,
                            schedule: String? = nil) -> String? {
        let parts = [onPower ? "plugged in" : nil, externalDisplay ? "a display is connected" : nil,
                     downloading ? "files are downloading" : nil, schedule].compactMap { $0 }
        guard let last = parts.last else { return nil }
        let head = parts.dropLast().joined(separator: ", ")
        return "while " + (head.isEmpty ? last : head + " and " + last)
    }
}

/// Keeps the Mac from idle-sleeping (like `caffeinate`), with sessions that end on a timer, when an app quits,
/// or when the battery gets low. Uses a power-management assertion, so `pmset -g assertions` shows it.
/// Closing the lid still sleeps the Mac; that needs root and isn't done here.
@Observable
@MainActor
final class KeepAwake {
    static let shared = KeepAwake()

    private(set) var session: AwakeSession?
    /// Why the last session ended by itself (cleared when a new one starts).
    private(set) var lastEndReason: AwakeEndReason?
    var isActive: Bool { session != nil }

    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var assertionKeepsDisplayOn: Bool?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var appObserver: NSObjectProtocol?
    @ObservationIgnored var batteryProvider: () -> BatterySample = { BatterySample() }
    /// Called when a session ends by itself (not when stopped by hand).
    @ObservationIgnored var onSessionEnded: ((AwakeEndReason) -> Void)?
    @ObservationIgnored private var triggerWasActive = false

    private var settings: AppSettings { .shared }

    func start(_ end: AwakeEnd, focus: Bool = false) {
        session = AwakeSession(started: Date(), end: end, focus: focus)
        lastEndReason = nil
        applyAssertion()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                MainActor.assumeIsolated { KeepAwake.shared.check() }
            }
        }
        if appObserver == nil {
            appObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
            ) { _ in MainActor.assumeIsolated { KeepAwake.shared.check() } }
        }
        NotificationCenter.default.post(name: .vibeCheckKeepAwakeChanged, object: nil)
    }

    func start(minutes: Int) { start(AwakePreset.end(minutes)) }

    /// Keeps the Mac awake for `minutes` of focus, then says to take a break.
    func startFocus(minutes: Int) { start(.at(Date().addingTimeInterval(Double(minutes) * 60)), focus: true) }

    /// Starts a session with the quick-start length from Settings, or stops the running one.
    func toggle() {
        if isActive { stop() } else { start(minutes: settings.keepAwakeDefaultMinutes) }
    }

    func stop(reason: AwakeEndReason? = nil) {
        guard session != nil else { return }
        session = nil
        lastEndReason = reason
        releaseAssertion()
        timer?.invalidate()
        timer = nil
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        appObserver = nil
        if let reason {
            NSLog("%@", "VibeCheck keep-awake ended: \(reason)")
            onSessionEnded?(reason)
        }
        NotificationCenter.default.post(name: .vibeCheckKeepAwakeChanged, object: nil)
    }

    /// Ends the session if its condition is met; also picks up a changed "keep display on" setting.
    func check(now: Date = Date()) {
        evaluateTriggers()
        guard let session else { return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if let reason = AwakeSession.endReason(session, now: now, battery: batteryProvider(),
                                               batteryFloor: settings.keepAwakeBatteryFloor,
                                               isRunning: running.contains) {
            stop(reason: reason)
        } else if assertionKeepsDisplayOn != settings.keepAwakeDisplayOn {
            applyAssertion()
        }
    }

    // MARK: Triggers

    private func evaluateTriggers() {
        let battery = batteryProvider()
        if settings.keepAwakeWhileDownloading {
            DownloadsWatcher.shared.refreshIfDue(folder: settings.downloadsFolderURL)
        }
        let active = AwakeTriggerAction.description(
            onPower: settings.keepAwakeOnPower && (!battery.present || battery.onAC),
            externalDisplay: settings.keepAwakeWithDisplay && Self.hasExternalDisplay(),
            downloading: settings.keepAwakeWhileDownloading && DownloadsWatcher.shared.isActive,
            schedule: settings.keepAwakeOnSchedule && settings.keepAwakeSchedule.isActive(at: Date())
                ? settings.keepAwakeSchedule.description() : nil)
        let action = AwakeTriggerAction.decide(active: active, wasActive: triggerWasActive, session: session)
        triggerWasActive = active != nil
        switch action {
        case .start(let description): start(.whileTriggered(description))
        case .stop: stop(reason: .triggerOff)
        case .none: break
        }
    }

    /// Any display that isn't the built-in panel (on a desktop Mac, any display).
    static func hasExternalDisplay() -> Bool {
        NSScreen.screens.contains { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(id.uint32Value) == 0
        }
    }

    // MARK: Power assertion

    private func applyAssertion() {
        let displayOn = settings.keepAwakeDisplayOn
        guard assertionKeepsDisplayOn != displayOn || assertionID == 0 else { return }
        releaseAssertion()
        // Display assertion keeps both the screen and the system awake; the system one lets the screen dim and sleep.
        let type = displayOn ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "VibeCheck keep awake" as CFString, &id)
        if result == kIOReturnSuccess {
            assertionID = id
            assertionKeepsDisplayOn = displayOn
        } else {
            NSLog("%@", "VibeCheck keep-awake: assertion failed (\(result))")
        }
    }

    private func releaseAssertion() {
        if assertionID != 0 { IOPMAssertionRelease(assertionID) }
        assertionID = 0
        assertionKeepsDisplayOn = nil
    }

    /// Apps someone might want to wait on: regular apps with a name, sorted, without VibeCheck itself.
    static func runningApps() -> [(bundleID: String, name: String)] {
        let own = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (String, String)? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != own,
                  let name = app.localizedName else { return nil }
            return (id, name)
        }
        var seen = Set<String>()
        return apps.filter { seen.insert($0.0).inserted }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
            .map { (bundleID: $0.0, name: $0.1) }
    }
}
