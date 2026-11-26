import Foundation
import Testing
@testable import VibeCheck

struct ClockFeaturesTests {
    @Test func offlineCitySearchFindsNonIANACitiesAndAbbreviations() {
        let sf = CityIndex.search("San Francisco")
        #expect(sf.first?.name == "San Francisco")
        #expect(sf.first?.timeZoneID == "America/Los_Angeles")

        let blr = CityIndex.search("Bangalore")
        #expect(blr.contains { $0.timeZoneID == "Asia/Kolkata" })

        let munich = CityIndex.search("Munich")
        #expect(munich.first?.timeZoneID == "Europe/Berlin")

        let npt = CityIndex.search("NPT")
        #expect(npt.contains { $0.timeZoneID == "Asia/Kathmandu" })

        #expect(CityIndex.search("   ").isEmpty)
    }

    @Test func customClockFormatAndWeekNumber() {
        let date = DateComponents(calendar: Calendar(identifier: .gregorian),
                                  timeZone: TimeZone(identifier: "UTC"),
                                  year: 2026, month: 11, day: 26, hour: 15, minute: 8, second: 42).date!
        let style = ClockFormatStyle(format: .custom, seconds: false, customFormat: "yyyy-MM-dd", showWeekNumber: true)
        let text = style.format(date)
        #expect(text.hasPrefix("W"))
        #expect(text.contains("2026-11-26"))

        // Empty custom pattern falls back cleanly instead of returning empty text.
        let fallback = ClockFormatStyle(format: .custom, seconds: false, customFormat: "   ", showWeekNumber: false)
        #expect(!fallback.format(date).isEmpty)

        #expect(ClockFormat.showsSeconds(format: .custom, showSeconds: false, customFormat: "HH:mm:ss"))
        #expect(!ClockFormat.showsSeconds(format: .custom, showSeconds: true, customFormat: "HH:mm"))
    }

    @Test func timeTravelSnappingAndLabels() {
        #expect(TimeTravel.snap(40, fine: false) == 60)
        #expect(TimeTravel.snap(40, fine: true) == 45)
        #expect(TimeTravel.snap(-900, fine: false) == -720)
        #expect(TimeTravel.snap(900, fine: true) == 720)

        #expect(TimeTravel.offsetLabel(minutes: 0) == "Now")
        #expect(TimeTravel.offsetLabel(minutes: 120) == "+2h")
        #expect(TimeTravel.offsetLabel(minutes: -90) == "−1h 30m")
        #expect(TimeTravel.offsetLabel(minutes: 45) == "+45m")
    }

    @Test func worldClockDecodesOldFormatAndFormatsTag() throws {
        let oldJSON = #"{"id":"11111111-1111-1111-1111-111111111111","name":"London","timeZoneID":"Europe/London"}"#
        let decoded = try JSONDecoder().decode(WorldClock.self, from: Data(oldJSON.utf8))
        #expect(decoded.name == "London")
        #expect(!decoded.showInMenuBar)
        #expect(decoded.menuBarTag == "LON")

        let nyc = WorldClock(name: "New York", timeZoneID: "America/New_York", showInMenuBar: true)
        #expect(nyc.menuBarTag == "NY")
        let utc = WorldClock(name: "UTC", timeZoneID: "UTC")
        #expect(utc.menuBarTag == "UTC")
    }

    @Test func calendarDateHelperRelativeLabels() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 10))!
        #expect(CalendarDateHelper.relativeDayLabel(for: today, today: today, calendar: cal) == "Today")
        #expect(CalendarDateHelper.relativeDayLabel(for: cal.date(byAdding: .day, value: 1, to: today)!, today: today, calendar: cal) == "Tomorrow")
        #expect(CalendarDateHelper.relativeDayLabel(for: cal.date(byAdding: .day, value: -1, to: today)!, today: today, calendar: cal) == "Yesterday")
        #expect(CalendarDateHelper.relativeDayLabel(for: cal.date(byAdding: .day, value: 5, to: today)!, today: today, calendar: cal) == "in 5 days")
        #expect(CalendarDateHelper.relativeDayLabel(for: cal.date(byAdding: .day, value: -3, to: today)!, today: today, calendar: cal) == "3 days ago")
    }

    @MainActor @Test func deckOpacityClampsAndPersists() {
        let name = "vibecheck.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: d)
        #expect(s.deckOpacity == 0)
        s.deckOpacity = 0.75
        #expect(s.deckOpacity == 0.75)
        s.deckOpacity = 1.5
        #expect(s.deckOpacity == 1.0)
        s.deckOpacity = -0.2
        #expect(s.deckOpacity == 0.0)
        s.deckOpacity = 0.6
        #expect(AppSettings(defaults: d).deckOpacity == 0.6)
    }

    @MainActor @Test func dateAndTimeRenameIconStylesAndPanelHeight() {
        #expect(Module.clock.title == "Date & Time")
        #expect(Module.clock.labelStyles.contains(.calendarIcon))
        #expect(Module.clock.labelStyles.contains(.calendarIconOnly))
        #expect(CalendarIconStyle.allCases.count == 4)

        let name = "vibecheck.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: d)
        s.clock.calendarIconStyle = .weekAndDay
        s.clock.panelHeight = 520
        let reloaded = AppSettings(defaults: d)
        #expect(reloaded.clock.calendarIconStyle == .weekAndDay)
        #expect(reloaded.clock.panelHeight == 520)

        reloaded.clock.panelHeight = 100
        #expect(reloaded.clock.panelHeight == 260)
        reloaded.clock.panelHeight = 0
        #expect(reloaded.clock.panelHeight == 0)
    }
}
