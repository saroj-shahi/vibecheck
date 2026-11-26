import Foundation
import Testing
@testable import VibeCheck

struct NextEventLogicTests {
    private func event(id: String, title: String, start: Date, minutes: Int = 30,
                       video: Bool = false, calID: String = "work", allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(
            id: id, eventID: id, title: title,
            startDate: start,
            endDate: start.addingTimeInterval(TimeInterval(minutes * 60)),
            isAllDay: allDay,
            calendarID: calID, calendarTitle: "Work",
            red: 0.2, green: 0.6, blue: 1.0,
            location: nil, notes: nil, url: nil,
            isRecurring: false, hasAlarms: true, isDeclined: false,
            attendeeNames: [],
            videoCall: video ? VideoCallLink(url: URL(string: "https://us02web.zoom.us/j/123456")!, service: .zoom) : nil
        )
    }

    @Test func respectsLookaheadVideoOnlyAndDismissedIDs() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let plain = event(id: "plain", title: "Coffee", start: now.addingTimeInterval(600), video: false)
        let call = event(id: "call", title: "Design Review", start: now.addingTimeInterval(1800), video: true)
        let far = event(id: "far", title: "Tomorrow", start: now.addingTimeInterval(30_000), video: true)

        let first = NextEventLogic.display(events: [plain, call, far], now: now, lookaheadMinutes: 240)
        #expect(first?.event.id == "plain")
        #expect(first?.countdown == "10m")

        let videoOnly = NextEventLogic.display(events: [plain, call, far], now: now, onlyVideoCalls: true, lookaheadMinutes: 240)
        #expect(videoOnly?.event.id == "call")

        let dismissed = NextEventLogic.display(events: [plain, call, far], now: now, dismissedEventIDs: ["plain", "call"], lookaheadMinutes: 240)
        #expect(dismissed == nil)
    }

    @Test func activeEventAndQuickJoinWindow() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let active = event(id: "a", title: "Standup", start: now.addingTimeInterval(-600), minutes: 30, video: true)
        let soon = event(id: "s", title: "1:1", start: now.addingTimeInterval(180), minutes: 30, video: true)
        let later = event(id: "l", title: "Demo", start: now.addingTimeInterval(900), minutes: 30, video: true)

        let activeDisplay = NextEventLogic.display(events: [active], now: now, showDuringEntireEvent: true)
        #expect(activeDisplay?.isHappening == true)
        #expect(activeDisplay?.canQuickJoin(at: now) == true)

        // When showDuringEntireEvent is off, active event is skipped.
        #expect(NextEventLogic.display(events: [active], now: now, showDuringEntireEvent: false) == nil)

        // Quick join applies within 5 min before start, not 15 min out.
        let soonDisplay = NextEventLogic.display(events: [soon], now: now)
        #expect(soonDisplay?.canQuickJoin(at: now) == true)

        let laterDisplay = NextEventLogic.display(events: [later], now: now)
        #expect(laterDisplay?.canQuickJoin(at: now) == false)
        // Inline Join pill appears within 15 min before start (and while active), when enabled.
        #expect(laterDisplay?.showsJoinPill(at: now, enabled: true) == true)
        #expect(laterDisplay?.showsJoinPill(at: now, enabled: false) == false)
        #expect(activeDisplay?.showsJoinPill(at: now, enabled: true) == true)

        let farCall = event(id: "fc", title: "Afternoon", start: now.addingTimeInterval(3600), minutes: 30, video: true)
        let farDisplay = NextEventLogic.display(events: [farCall], now: now)
        #expect(farDisplay?.showsJoinPill(at: now, enabled: true) == false)
    }
}
