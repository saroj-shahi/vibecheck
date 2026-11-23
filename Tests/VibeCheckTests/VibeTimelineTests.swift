import Testing
import Foundation
@testable import VibeCheck

struct VibeTimelineTests {
    static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US")
        return c
    }
    static func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2025, month: 11, day: d, hour: h, minute: m))!
    }
    static func ep(_ a: Date, _ b: Date, _ vibe: Vibe, _ culprit: Module? = .cpu) -> VibeEpisode {
        VibeEpisode(start: a.timeIntervalSince1970, end: b.timeIntervalSince1970,
                    worst: vibe.rawValue, culprit: culprit?.rawValue, process: nil)
    }

    @Test func bucketsMinutesAndCulprit() {
        let now = Self.date(20, 12)
        let eps = [Self.ep(Self.date(20, 9), Self.date(20, 9, 42), .mid),
                   Self.ep(Self.date(20, 10), Self.date(20, 10, 9), .cooked, .cpu)]
        let days = VibeReplayStore.dayBuckets(eps, days: 7, now: now, calendar: Self.cal)
        #expect(days.count == 7)
        let today = days.last!
        #expect(Self.cal.isDate(today.start, inSameDayAs: now))
        #expect(today.midMinutes == 42)
        #expect(today.cookedMinutes == 9)
        #expect(today.culprit == Module.cpu.title)
        #expect(today.pieces.count == 2)
        #expect(days.first!.totalMinutes == 0)
    }

    @Test func splitsAtMidnight() {
        let now = Self.date(20, 12)
        let eps = [Self.ep(Self.date(19, 23), Self.date(20, 1), .cooked)]
        let days = VibeReplayStore.dayBuckets(eps, days: 30, now: now, calendar: Self.cal)
        #expect(days.count == 30)
        #expect(days[28].cookedMinutes == 60)
        #expect(days[29].cookedMinutes == 60)
        #expect(days[28].pieces.first!.end == 1)
        #expect(days[29].pieces.first!.start == 0)
    }

    @Test func description() {
        let now = Self.date(18, 12)
        let eps = [Self.ep(Self.date(18, 9), Self.date(18, 9, 42), .mid),
                   Self.ep(Self.date(18, 10), Self.date(18, 10, 9), .cooked)]
        let day = VibeReplayStore.dayBuckets(eps, days: 1, now: now, calendar: Self.cal)[0]
        let text = VibeReplayStore.dayDescription(day, calendar: Self.cal)
        #expect(text.contains("42 min mid"))
        #expect(text.contains("9 min cooked"))
        #expect(text.contains("mostly"))
        #expect(VibeReplayStore.dayLabel(day, now: now, calendar: Self.cal) == "Today")
    }
}
