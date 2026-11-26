import Foundation
import Testing
@testable import VibeCheck

struct CalendarAndVideoCallTests {
    // MARK: - VideoCallDetector

    @Test func detectsMajorVideoCallServices() {
        let cases: [(String, VideoCallService)] = [
            ("https://us02web.zoom.us/j/81234567890?pwd=abc", .zoom),
            ("zoommtg://zoom.us/join?confno=123456", .zoom),
            ("https://meet.google.com/abc-defg-hij", .googleMeet),
            ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_xyz/0", .microsoftTeams),
            ("https://teams.live.com/meet/934812345", .microsoftTeams),
            ("https://acme.webex.com/acme/j.php?MTID=m123", .webex),
            ("https://facetime.apple.com/join#v=1&p=abc", .faceTime),
            ("https://app.slack.com/huddle/T123/C456", .slack),
            ("https://tuple.app/c/abc123", .tuple),
            ("https://whereby.com/team-standup", .whereby),
            ("https://meet.jit.si/vibecheck-sync", .jitsi),
            ("https://discord.gg/abcdef", .discord),
            ("https://app.cal.com/video/standup", .calCom),
            ("https://app.gather.town/app/xyz/office", .gather),
        ]
        for (raw, expected) in cases {
            let link = VideoCallDetector.detect(url: nil, location: nil, notes: "Join here: \(raw).")
            #expect(link?.service == expected, "Expected \(expected) for \(raw)")
        }
    }

    @Test func unwrapsSafeLinksAndIgnoresNonMeetingPages() {
        let wrapped = "https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fmeet.google.com%2Fxyz-abcd-efg&data=1"
        let link = VideoCallDetector.detect(url: URL(string: wrapped), location: nil, notes: nil)
        #expect(link?.service == .googleMeet)
        #expect(link?.url.host == "meet.google.com")

        // Generic marketing / docs pages must not trigger Join buttons.
        #expect(VideoCallDetector.detect(url: URL(string: "https://zoom.us/pricing"), location: nil, notes: nil) == nil)
        #expect(VideoCallDetector.detect(url: URL(string: "https://meet.google.com/about"), location: nil, notes: nil) == nil)
        #expect(VideoCallDetector.detect(url: URL(string: "https://github.com/saroj-shahi/vibecheck"), location: nil, notes: nil) == nil)

        // Custom domain support.
        let custom = VideoCallDetector.detect(url: URL(string: "https://meet.company.internal/room/1"),
                                              location: nil, notes: nil,
                                              customDomains: ["meet.company.internal"])
        #expect(custom?.service == .custom)
    }

    // MARK: - CalendarLogic

    private func makeEvent(id: String = "e1", title: String = "Standup",
                           start: Date, durationMinutes: Int = 30,
                           allDay: Bool = false, calID: String = "work",
                           declined: Bool = false, hasVideo: Bool = false) -> CalendarEvent {
        CalendarEvent(
            id: "\(id)|\(Int(start.timeIntervalSince1970))",
            eventID: id,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(TimeInterval(durationMinutes * 60)),
            isAllDay: allDay,
            calendarID: calID,
            calendarTitle: calID.capitalized,
            red: 0.2, green: 0.6, blue: 1.0,
            location: nil,
            notes: nil,
            url: nil,
            isRecurring: false,
            hasAlarms: true,
            isDeclined: declined,
            attendeeNames: [],
            videoCall: hasVideo ? VideoCallLink(url: URL(string: "https://meet.google.com/aaa-bbbb-ccc")!, service: .googleMeet) : nil
        )
    }

    @Test func deduplicatesEventsPreferringVideoCallCopy() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let plain = makeEvent(id: "e1", title: "Weekly Sync", start: now, calID: "icloud", hasVideo: false)
        let withCall = makeEvent(id: "e2", title: "  weekly sync ", start: now, calID: "google", hasVideo: true)
        let deduped = CalendarLogic.deduplicate([plain, withCall])
        #expect(deduped.count == 1)
        #expect(deduped[0].videoCall?.service == .googleMeet)
    }

    @Test func filtersHiddenCalendarsDeclinedAllDayAndPastToday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 12))!
        let past = makeEvent(id: "p", title: "Morning", start: now.addingTimeInterval(-7200), durationMinutes: 30)
        let upcoming = makeEvent(id: "u", title: "Afternoon", start: now.addingTimeInterval(3600), durationMinutes: 30)
        let allDay = makeEvent(id: "a", title: "Holiday", start: cal.startOfDay(for: now), durationMinutes: 1440, allDay: true)
        let declined = makeEvent(id: "d", title: "Skipped", start: now.addingTimeInterval(1800), declined: true)
        let hidden = makeEvent(id: "h", title: "Personal", start: now.addingTimeInterval(1800), calID: "personal")

        let filtered = CalendarLogic.filter([past, upcoming, allDay, declined, hidden],
                                            hiddenCalendarIDs: ["personal"],
                                            showAllDay: false,
                                            hidePastToday: true,
                                            now: now,
                                            calendar: cal)
        #expect(filtered.map(\.eventID) == ["u"])
    }

    @Test func nextJoinableCallAndCountdown() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let running = makeEvent(id: "r", title: "Current", start: now.addingTimeInterval(-600), durationMinutes: 30, hasVideo: true)
        let soon = makeEvent(id: "s", title: "Next", start: now.addingTimeInterval(240), durationMinutes: 30, hasVideo: true)
        let far = makeEvent(id: "f", title: "Later", start: now.addingTimeInterval(3600), durationMinutes: 30, hasVideo: true)

        // Starting within 5 min takes priority over an ongoing call.
        #expect(CalendarLogic.nextJoinableCall(in: [running, soon, far], now: now)?.eventID == "s")
        #expect(CalendarLogic.nextJoinableCall(in: [far], now: now, lookaheadMinutes: 15) == nil)
        #expect(CalendarLogic.countdownText(for: soon, now: now) == "in 4m")
        #expect(CalendarLogic.countdownText(for: running, now: now) == "20m left")
    }
}
