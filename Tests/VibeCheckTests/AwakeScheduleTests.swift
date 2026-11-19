import Foundation
import Testing
@testable import VibeCheck

struct AwakeScheduleTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    /// 2026-11-16 is a Monday.
    private func date(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func weekdaysNineToFive() {
        let s = AwakeSchedule(days: AwakeSchedule.weekdays, startMinute: 9 * 60, endMinute: 17 * 60)
        #expect(s.isActive(at: date(day: 16, 9), calendar: calendar))           // Monday 9:00, start included
        #expect(s.isActive(at: date(day: 20, 16, 59), calendar: calendar))      // Friday 16:59
        #expect(!s.isActive(at: date(day: 20, 17), calendar: calendar))         // end excluded
        #expect(!s.isActive(at: date(day: 16, 8, 59), calendar: calendar))
        #expect(!s.isActive(at: date(day: 21, 12), calendar: calendar))         // Saturday
        #expect(!s.isActive(at: date(day: 22, 12), calendar: calendar))         // Sunday
    }

    @Test func overnightBelongsToTheStartDay() {
        let saturdayNight = AwakeSchedule(days: 1 << 7, startMinute: 22 * 60, endMinute: 2 * 60)
        #expect(saturdayNight.isActive(at: date(day: 21, 23), calendar: calendar))   // Saturday 23:00
        #expect(saturdayNight.isActive(at: date(day: 22, 1), calendar: calendar))    // Sunday 01:00, wraps 7 → 1
        #expect(!saturdayNight.isActive(at: date(day: 22, 23), calendar: calendar))  // Sunday night: not on
        #expect(!saturdayNight.isActive(at: date(day: 21, 1), calendar: calendar))   // Saturday 01:00 is Friday's
    }

    @Test func emptyWindowOrNoDaysNeverActive() {
        #expect(!AwakeSchedule(days: AwakeSchedule.weekdays, startMinute: 600, endMinute: 600)
            .isActive(at: date(day: 16, 10), calendar: calendar))
        #expect(!AwakeSchedule(days: 0, startMinute: 0, endMinute: 1439)
            .isActive(at: date(day: 16, 10), calendar: calendar))
    }

    @Test func wording() {
        let s = AwakeSchedule(days: AwakeSchedule.weekdays, startMinute: 9 * 60, endMinute: 17 * 60)
        #expect(s.description(now: date(day: 16, 10), calendar: calendar).hasPrefix("within your schedule (until "))
        #expect(AwakeTriggerAction.description(onPower: true, externalDisplay: false, schedule: "within your schedule")
                == "while plugged in and within your schedule")
    }
}
