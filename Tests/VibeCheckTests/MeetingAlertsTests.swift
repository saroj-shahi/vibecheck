import Foundation
import Testing
@testable import VibeCheck

struct MeetingAlertsTests {
    private func makeEvent(id: String, start: Date, video: Bool = true, alarm: Bool = true,
                           allDay: Bool = false, declined: Bool = false, calID: String = "work") -> CalendarEvent {
        CalendarEvent(
            id: id, eventID: id, title: "Meeting \(id)",
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            isAllDay: allDay,
            calendarID: calID, calendarTitle: "Work",
            red: 0.2, green: 0.6, blue: 1.0,
            location: nil, notes: nil, url: nil,
            isRecurring: false, hasAlarms: alarm, isDeclined: declined,
            attendeeNames: [],
            videoCall: video ? VideoCallLink(url: URL(string: "https://meet.google.com/abc-defg-hij")!, service: .googleMeet) : nil
        )
    }

    @Test func schedulesEarliestEligibleEventWithLeadTimeAndSnooze() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let e1 = makeEvent(id: "e1", start: now.addingTimeInterval(300), video: false)
        let e2 = makeEvent(id: "e2", start: now.addingTimeInterval(600), video: true)
        let e3 = makeEvent(id: "e3", start: now.addingTimeInterval(900), video: true, alarm: false)

        var cfg = MeetingAlertPolicy.Config(style: .fullscreen, leadMinutes: 2, onlyVideoCalls: true, onlyWithAlarm: true)
        let next = MeetingAlertPolicy.nextAlert(events: [e1, e2, e3], now: now, firedIDs: [], snoozedUntil: [:], config: cfg)
        #expect(next?.event.id == "e2")
        #expect(next?.fireAt == e2.startDate.addingTimeInterval(-120))

        // Once fired, e2 is skipped unless snoozed.
        let afterFired = MeetingAlertPolicy.nextAlert(events: [e1, e2, e3], now: now, firedIDs: ["e2"], snoozedUntil: [:], config: cfg)
        #expect(afterFired == nil)

        let snoozeTarget = now.addingTimeInterval(180)
        let snoozed = MeetingAlertPolicy.nextAlert(events: [e1, e2, e3], now: now, firedIDs: ["e2"], snoozedUntil: ["e2": snoozeTarget], config: cfg)
        #expect(snoozed?.event.id == "e2")
        #expect(snoozed?.fireAt == snoozeTarget)

        // When style is .off, nothing schedules.
        cfg.style = .off
        #expect(MeetingAlertPolicy.nextAlert(events: [e2], now: now, firedIDs: [], snoozedUntil: [:], config: cfg) == nil)
    }

    @Test func deliveryDecisionSuppressesOrDowngradesAppropriately() {
        #expect(MeetingAlertPolicy.deliveryDecision(style: .fullscreen, isMirrored: false, inCall: false,
                                                    focusPaused: false, screenLocked: false,
                                                    suppressDuringCall: true, suppressWhenMirrored: true) == .fullscreen)

        // Mirrored display downgrades fullscreen to quiet banner.
        #expect(MeetingAlertPolicy.deliveryDecision(style: .fullscreen, isMirrored: true, inCall: false,
                                                    focusPaused: false, screenLocked: false,
                                                    suppressDuringCall: true, suppressWhenMirrored: true) == .downgradedBanner)

        // Active call downgrades when suppressDuringCall is true.
        #expect(MeetingAlertPolicy.deliveryDecision(style: .fullscreen, isMirrored: false, inCall: true,
                                                    focusPaused: false, screenLocked: false,
                                                    suppressDuringCall: true, suppressWhenMirrored: true) == .downgradedBanner)

        // Focus filter or locked screen suppresses completely.
        #expect(MeetingAlertPolicy.deliveryDecision(style: .fullscreen, isMirrored: false, inCall: false,
                                                    focusPaused: true, screenLocked: false,
                                                    suppressDuringCall: true, suppressWhenMirrored: true) == .suppressed)
        #expect(MeetingAlertPolicy.deliveryDecision(style: .banner, isMirrored: false, inCall: false,
                                                    focusPaused: false, screenLocked: true,
                                                    suppressDuringCall: true, suppressWhenMirrored: true) == .suppressed)
    }

    @Test func focusFilterStateDecodesLegacyJSONAndSupportsNewFlags() throws {
        let legacy = #"{"holdAlerts":true,"keepDisplayAwake":false}"#
        let decoded = try JSONDecoder().decode(FocusFilterState.self, from: Data(legacy.utf8))
        #expect(decoded.holdAlerts)
        #expect(!decoded.pauseMeetingAlerts)
        #expect(!decoded.pauseHourlyChime)

        let paused = FocusFilterState(pauseMeetingAlerts: true, pauseHourlyChime: true)
        #expect(FocusFilterState.suppressMeetingAlerts(focus: paused))
        #expect(FocusFilterState.suppressHourlyChime(focus: paused))
    }
}
