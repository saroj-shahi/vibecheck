import Foundation
import Testing
@testable import VibeCheck

struct HourlyChimeAndTimeCalcTests {
    // MARK: - HourlyChimeLogic

    @Test func nextFireDateAlignsToHourOrHalfHour() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let at1012 = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 10, minute: 12, second: 30))!
        let at1045 = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 10, minute: 45, second: 0))!

        let nextHour = HourlyChimeLogic.nextFireDate(after: at1012, cadence: .hourly, calendar: cal)
        #expect(cal.component(.hour, from: nextHour) == 11)
        #expect(cal.component(.minute, from: nextHour) == 0)

        let nextHalf1 = HourlyChimeLogic.nextFireDate(after: at1012, cadence: .halfHourly, calendar: cal)
        #expect(cal.component(.hour, from: nextHalf1) == 10)
        #expect(cal.component(.minute, from: nextHalf1) == 30)

        let nextHalf2 = HourlyChimeLogic.nextFireDate(after: at1045, cadence: .halfHourly, calendar: cal)
        #expect(cal.component(.hour, from: nextHalf2) == 11)
        #expect(cal.component(.minute, from: nextHalf2) == 0)
    }

    @Test func shouldChimeRespectsActiveHoursAndSuppression() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let noon = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 12, minute: 0))!
        let late = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 22, minute: 0))!

        #expect(HourlyChimeLogic.shouldChime(at: noon, enabled: true, startMinute: 9 * 60, endMinute: 18 * 60,
                                             inCall: false, focusPaused: false, screenLocked: false, calendar: cal))
        #expect(!HourlyChimeLogic.shouldChime(at: late, enabled: true, startMinute: 9 * 60, endMinute: 18 * 60,
                                              inCall: false, focusPaused: false, screenLocked: false, calendar: cal))
        #expect(!HourlyChimeLogic.shouldChime(at: noon, enabled: true, startMinute: 9 * 60, endMinute: 18 * 60,
                                              inCall: true, focusPaused: false, screenLocked: false, calendar: cal))
        #expect(!HourlyChimeLogic.shouldChime(at: noon, enabled: true, startMinute: 9 * 60, endMinute: 18 * 60,
                                              inCall: false, focusPaused: true, screenLocked: false, calendar: cal))
    }

    // MARK: - TimeCalculator

    @Test func evaluatesTimeZoneConversion() {
        var cal = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!
        cal.timeZone = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 10, minute: 0))!

        let est = TimeCalculator.evaluate("3pm EST", now: now, localTimeZone: utc, calendar: cal)
        #expect(est != nil)
        #expect(est!.title.contains("EST"))
        #expect(est!.title.contains("→"))

        let tokyo = TimeCalculator.evaluate("14:30 Tokyo", now: now, localTimeZone: utc, calendar: cal)
        #expect(tokyo != nil)
        #expect(tokyo!.title.contains("Tokyo"))

        // Plain command words must not falsely trigger the calculator.
        #expect(TimeCalculator.evaluate("keep awake", now: now, localTimeZone: utc, calendar: cal) == nil)
        #expect(TimeCalculator.evaluate("cpu", now: now, localTimeZone: utc, calendar: cal) == nil)
    }

    @Test func evaluatesRelativeOffsetsAndDurations() {
        var cal = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!
        cal.timeZone = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 10, minute: 0))!

        let plus45d = TimeCalculator.evaluate("today + 45d", now: now, localTimeZone: utc, calendar: cal)
        #expect(plus45d != nil)
        #expect(plus45d!.copyValue.contains("2027"))

        let plus3h = TimeCalculator.evaluate("now + 3h30m", now: now, localTimeZone: utc, calendar: cal)
        #expect(plus3h != nil)

        let daysUntil = TimeCalculator.evaluate("days until 2026-12-31", now: now, localTimeZone: utc, calendar: cal)
        #expect(daysUntil?.copyValue == "35 days")

        let weeksUntil = TimeCalculator.evaluate("weeks until 2026-12-31", now: now, localTimeZone: utc, calendar: cal)
        #expect(weeksUntil?.copyValue == "5 weeks")

        let daysSince = TimeCalculator.evaluate("days since 2026-11-20", now: now, localTimeZone: utc, calendar: cal)
        #expect(daysSince?.copyValue == "6 days")
    }
}
