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
}

/// Why a session stopped by itself.
enum AwakeEndReason: Equatable {
    case timeUp, appQuit, lowBattery

    var message: String {
        switch self {
        case .timeUp: "Time's up."
        case .appQuit: "The app it was waiting on quit."
        case .lowBattery: "The battery got low."
        }
    }
}

struct AwakeSession: Equatable {
    var started: Date
    var end: AwakeEnd

    /// Checks the session's end condition and the battery floor (0 = no floor). Plain function so it's testable.
    static func endReason(_ session: AwakeSession, now: Date, battery: BatterySample, batteryFloor: Int,
                          isRunning: (String) -> Bool) -> AwakeEndReason? {
        switch session.end {
        case .never: break
        case .at(let date): if now >= date { return .timeUp }
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
        case .at(let date):
            let minutes = max(0, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
            if minutes < 60 { return "\(max(minutes, 1)) min left" }
            let hours = minutes / 60, rest = minutes % 60
            return rest == 0 ? "\(hours) h left" : "\(hours) h \(rest) min left"
        }
    }
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

    private var settings: AppSettings { .shared }

    func start(_ end: AwakeEnd) {
        session = AwakeSession(started: Date(), end: end)
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
        if let reason { NSLog("%@", "VibeCheck keep-awake ended: \(reason)") }
        NotificationCenter.default.post(name: .vibeCheckKeepAwakeChanged, object: nil)
    }

    /// Ends the session if its condition is met; also picks up a changed "keep display on" setting.
    func check(now: Date = Date()) {
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
