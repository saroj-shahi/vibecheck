import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// How VibeCheck notifies you when an upcoming calendar event is about to start.
enum MeetingAlertStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case off, banner, fullscreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: String(localized: "Off")
        case .banner: String(localized: "Notification banner")
        case .fullscreen: String(localized: "Fullscreen alert")
        }
    }
}

/// Pure scheduling and suppression rules for meeting alerts (unit-tested with no AppKit/EventKit dependency).
enum MeetingAlertPolicy {
    struct Config: Equatable, Sendable {
        var style: MeetingAlertStyle = .off
        var leadMinutes: Int = 1
        var onlyVideoCalls: Bool = true
        var onlyWithAlarm: Bool = false
        var hiddenCalendarIDs: Set<String> = []
        var suppressDuringCall: Bool = true
        var suppressWhenMirrored: Bool = true
    }

    enum DeliveryDecision: Equatable, Sendable {
        case fullscreen
        case downgradedBanner
        case suppressed
    }

    struct ScheduledAlert: Equatable, Sendable {
        let event: CalendarEvent
        let fireAt: Date
    }

    /// Finds the single earliest eligible meeting alert to schedule (or fire immediately if due now).
    nonisolated static func nextAlert(events: [CalendarEvent],
                                      now: Date,
                                      firedIDs: Set<String>,
                                      snoozedUntil: [String: Date],
                                      config: Config) -> ScheduledAlert? {
        guard config.style != .off else { return nil }
        let leadSeconds = TimeInterval(max(0, config.leadMinutes) * 60)
        var best: ScheduledAlert?

        for event in events {
            guard !event.isAllDay, !event.isDeclined, !config.hiddenCalendarIDs.contains(event.calendarID) else { continue }
            guard event.endDate > now else { continue }
            if config.onlyVideoCalls && event.videoCall == nil { continue }
            if config.onlyWithAlarm && !event.hasAlarms { continue }

            let fireAt: Date
            if let snooze = snoozedUntil[event.id] {
                fireAt = snooze
            } else {
                guard !firedIDs.contains(event.id) else { continue }
                let natural = event.startDate.addingTimeInterval(-leadSeconds)
                // Don't fire retroactively for meetings that started more than 2 minutes ago.
                guard now.timeIntervalSince(event.startDate) <= 120 else { continue }
                fireAt = natural
            }

            if let current = best {
                if fireAt < current.fireAt { best = ScheduledAlert(event: event, fireAt: fireAt) }
            } else {
                best = ScheduledAlert(event: event, fireAt: fireAt)
            }
        }
        return best
    }

    /// Decides whether to show fullscreen, quietly downgrade to a system banner, or suppress altogether.
    nonisolated static func deliveryDecision(style: MeetingAlertStyle,
                                             isMirrored: Bool,
                                             inCall: Bool,
                                             focusPaused: Bool,
                                             screenLocked: Bool,
                                             suppressDuringCall: Bool,
                                             suppressWhenMirrored: Bool) -> DeliveryDecision {
        guard style != .off, !focusPaused, !screenLocked else { return .suppressed }
        if style == .banner { return .downgradedBanner }
        if (suppressWhenMirrored && isMirrored) || (suppressDuringCall && inCall) {
            return .downgradedBanner
        }
        return .fullscreen
    }

    /// True if any connected display is mirrored (e.g. AirPlay / projector) — requires no privacy permission.
    @MainActor
    static func isAnyDisplayMirrored() -> Bool {
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                if CGDisplayIsInMirrorSet(CGDirectDisplayID(number.uint32Value)) != 0 {
                    return true
                }
            }
        }
        return false
    }

    /// True when the macOS login session screen is locked.
    nonisolated static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}

/// Schedules a single next-meeting timer and presents fullscreen alerts across all connected displays
/// (or downgrades to a banner when presenting / already in a call).
@MainActor
final class MeetingAlertManager {
    static let shared = MeetingAlertManager()

    private weak var alerts: AlertEngine?
    private var timer: Timer?
    private var firedIDs: Set<String> = []
    private var snoozedUntil: [String: Date] = [:]
    private var panels: [NSPanel] = []
    private var keyMonitor: Any?
    private var activeEvent: CalendarEvent?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    func start(alerts: AlertEngine) {
        self.alerts = alerts
        guard observers.isEmpty else { reschedule(); return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .vibeCheckCalendarChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reschedule() }
        })
        observers.append(nc.addObserver(forName: .vibeCheckSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reschedule() }
        })
        reschedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        dismissFullscreen()
    }

    func reschedule() {
        timer?.invalidate()
        timer = nil

        let config = currentConfig()
        guard config.style != .off, CalendarStore.shared.access == .granted else { return }

        let now = Date()
        guard let next = MeetingAlertPolicy.nextAlert(events: CalendarStore.shared.events,
                                                      now: now,
                                                      firedIDs: firedIDs,
                                                      snoozedUntil: snoozedUntil,
                                                      config: config) else { return }

        let delay = next.fireAt.timeIntervalSince(now)
        if delay <= 1 {
            trigger(next.event, config: config)
        } else {
            let t = Timer(timeInterval: min(delay, 3600), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.reschedule() }
            }
            t.tolerance = 0.5
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    /// Shows a realistic sample fullscreen overlay from Settings so the user can preview it immediately.
    func showPreview() {
        let now = Date()
        let sample = CalendarEvent(
            id: "preview-\(UUID().uuidString)",
            eventID: "preview",
            title: String(localized: "Weekly Design Sync"),
            startDate: now.addingTimeInterval(60),
            endDate: now.addingTimeInterval(1860),
            isAllDay: false,
            calendarID: "preview",
            calendarTitle: String(localized: "Work"),
            red: 0.22, green: 0.68, blue: 0.96,
            location: nil,
            notes: nil,
            url: URL(string: "https://meet.google.com/abc-defg-hij"),
            isRecurring: true,
            hasAlarms: true,
            isDeclined: false,
            attendeeNames: ["Alex", "Sam"],
            videoCall: VideoCallLink(url: URL(string: "https://meet.google.com/abc-defg-hij")!, service: .googleMeet)
        )
        presentFullscreen(sample, isPreview: true)
    }

    func dismissFullscreen() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        activeEvent = nil
    }

    // MARK: - Private

    private func currentConfig() -> MeetingAlertPolicy.Config {
        let c = AppSettings.shared.clock
        return MeetingAlertPolicy.Config(
            style: c.meetingAlertStyle,
            leadMinutes: c.meetingAlertLeadMinutes,
            onlyVideoCalls: c.meetingAlertOnlyVideoCalls,
            onlyWithAlarm: c.meetingAlertOnlyWithAlarm,
            hiddenCalendarIDs: c.hiddenCalendarIDs,
            suppressDuringCall: c.meetingAlertSuppressDuringCall,
            suppressWhenMirrored: true
        )
    }

    private func trigger(_ event: CalendarEvent, config: MeetingAlertPolicy.Config) {
        firedIDs.insert(event.id)
        snoozedUntil.removeValue(forKey: event.id)
        // Keep fired set bounded across multi-day runs.
        if firedIDs.count > 200 { firedIDs.removeAll(); firedIDs.insert(event.id) }

        let decision = MeetingAlertPolicy.deliveryDecision(
            style: config.style,
            isMirrored: MeetingAlertPolicy.isAnyDisplayMirrored(),
            inCall: CallGuard.shared.inCall,
            focusPaused: FocusFilterState.suppressMeetingAlerts(focus: FocusFilterStore.shared.state),
            screenLocked: MeetingAlertPolicy.isScreenLocked(),
            suppressDuringCall: config.suppressDuringCall,
            suppressWhenMirrored: config.suppressWhenMirrored
        )

        switch decision {
        case .suppressed:
            break
        case .downgradedBanner:
            let countdown = CalendarLogic.countdownText(for: event, now: Date())
            let body = event.videoCall.map { String(localized: "Starts \(countdown) · \($0.service.title)") }
                ?? String(localized: "Starts \(countdown)")
            alerts?.notifyMeeting(title: event.title, body: body, joinURL: event.videoCall?.url)
        case .fullscreen:
            presentFullscreen(event, isPreview: false)
        }
        reschedule()
    }

    private func presentFullscreen(_ event: CalendarEvent, isPreview: Bool) {
        dismissFullscreen()
        activeEvent = event

        if AppSettings.shared.clock.meetingAlertPlaySound {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        for screen in screens {
            let panel = MeetingAlertPanel(contentRect: screen.frame,
                                          styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered,
                                          defer: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false

            let view = MeetingAlertView(
                event: event,
                isPreview: isPreview,
                onJoin: { [weak self] in
                    if !isPreview, let url = event.videoCall?.url {
                        NSWorkspace.shared.open(url)
                    }
                    self?.dismissFullscreen()
                },
                onSnooze: { [weak self] minutes in
                    guard let self else { return }
                    self.dismissFullscreen()
                    if !isPreview {
                        self.snoozedUntil[event.id] = Date().addingTimeInterval(TimeInterval(minutes * 60))
                        self.reschedule()
                    }
                },
                onOpenCalendar: { [weak self] in
                    self?.dismissFullscreen()
                    if !isPreview { CalendarDateHelper.openCalendarApp(at: event.startDate) }
                },
                onDismiss: { [weak self] in
                    self?.dismissFullscreen()
                }
            )
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: screen.frame.size)
            panel.contentView = host
            panel.setFrame(screen.frame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                panel.animator().alphaValue = 1
            }
            panels.append(panel)
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] keyEvent in
            let code = keyEvent.keyCode
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let active = self.activeEvent else { return false }
                switch code {
                case 53: // Esc
                    self.dismissFullscreen()
                    return true
                case 36, 76: // Return / Enter
                    if !isPreview, let url = active.videoCall?.url {
                        NSWorkspace.shared.open(url)
                    }
                    self.dismissFullscreen()
                    return true
                default:
                    return false
                }
            }
            return handled ? nil : keyEvent
        }
    }
}

private final class MeetingAlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
