import AppKit
import Foundation
import os
import Observation

/// What the Date & Time menu bar calendar icon displays.
enum CalendarIconStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case day, weekdayAndDay, weekAndDay, week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: String(localized: "Date (26)")
        case .weekdayAndDay: String(localized: "Weekday & date (Thu 26)")
        case .weekAndDay: String(localized: "Week & date (W48 · 26)")
        case .week: String(localized: "Week number (W48)")
        }
    }
}

/// Menu bar clock formats. Presets adapt to the user's locale (12/24-hour, day/month order);
/// `.custom` accepts a Unicode date format pattern (e.g. `EEE d MMM HH:mm`).
enum ClockFormat: String, CaseIterable, Identifiable, Codable {
    case time, dayTime, dateTime, time24, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time: String(localized: "Time")
        case .dayTime: String(localized: "Day & time")
        case .dateTime: String(localized: "Date & time")
        case .time24: String(localized: "24-hour time")
        case .custom: String(localized: "Custom…")
        }
    }

    func template(seconds: Bool) -> String {
        let s = seconds ? "ss" : ""
        switch self {
        case .time: return "jmm\(s)"
        case .dayTime: return "EEEjmm\(s)"
        case .dateTime: return "EEEdMMMjmm\(s)"
        case .time24: return "HHmm\(s)"
        case .custom: return "EEEjmm\(s)"
        }
    }

    func formatter(seconds: Bool, customFormat: String = "") -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .current
        let trimmed = customFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        if self == .custom, !trimmed.isEmpty {
            formatter.dateFormat = trimmed
        } else {
            formatter.setLocalizedDateFormatFromTemplate(template(seconds: seconds))
        }
        return formatter
    }

    /// True when the active format displays seconds (needs 1 Hz ticking).
    nonisolated static func showsSeconds(format: ClockFormat, showSeconds: Bool, customFormat: String) -> Bool {
        if format == .custom {
            let trimmed = customFormat.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed.contains("s") || trimmed.contains("S") }
        }
        return showSeconds
    }
}

/// Format style used by SwiftUI `Text(date, format:)`.
struct ClockFormatStyle: FormatStyle {
    let format: ClockFormat
    let seconds: Bool
    var customFormat: String = ""
    var showWeekNumber: Bool = false

    func format(_ value: Date) -> String {
        let base = Self.cache(format, seconds, customFormat).string(from: value)
        guard showWeekNumber else { return base }
        let week = CalendarDateHelper.weekNumber(for: value)
        return "W\(week) \(base)"
    }

    private static func cache(_ format: ClockFormat, _ seconds: Bool, _ customFormat: String) -> DateFormatter {
        // DateFormatter is expensive to create; reuse one per format. The lock makes the cache safe when
        // SwiftUI formats off the main thread (formatting itself is thread-safe on macOS 10.9+).
        let key = "\(format.rawValue)-\(seconds)-\(format == .custom ? customFormat : "")"
        return formatters.withLock { cache in
            if let cached = cache[key] { return cached }
            let made = format.formatter(seconds: seconds, customFormat: customFormat)
            cache[key] = made
            return made
        }
    }

    private static let formatters = OSAllocatedUnfairLock<[String: DateFormatter]>(uncheckedState: [:])
}

struct WorldClock: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var timeZoneID: String
    /// Optional compact badge shown next to the local clock in the menu bar.
    var showInMenuBar: Bool = false

    init(id: UUID = UUID(), name: String, timeZoneID: String, showInMenuBar: Bool = false) {
        self.id = id
        self.name = name
        self.timeZoneID = timeZoneID
        self.showInMenuBar = showInMenuBar
    }

    /// Backward-compatible decode so saved clocks from earlier versions keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        timeZoneID = try c.decode(String.self, forKey: .timeZoneID)
        showInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? false
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .gmt }

    /// Short menu bar prefix (e.g. "UTC", "LON", "NYC" or first 6 characters).
    var menuBarTag: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return timeZone.abbreviation() ?? "TZ" }
        if trimmed.count <= 4 { return trimmed }
        let words = trimmed.split(separator: " ")
        if words.count >= 2 {
            let initials = words.prefix(3).compactMap(\.first).map(String.init).joined().uppercased()
            if initials.count >= 2 { return initials }
        }
        return String(trimmed.prefix(3)).uppercased()
    }

    static let defaults = [
        WorldClock(name: "UTC", timeZoneID: "UTC"),
        WorldClock(name: "London", timeZoneID: "Europe/London"),
        WorldClock(name: "New York", timeZoneID: "America/New_York"),
    ]

    /// "America/New_York" → "New York"
    nonisolated static func cityName(_ identifier: String) -> String {
        (identifier.split(separator: "/").last.map(String.init) ?? identifier).replacingOccurrences(of: "_", with: " ")
    }

    /// e.g. "Today, +5:45", "Tomorrow, +10", "Same time"
    nonisolated func relativeDescription(at now: Date, localTimeZone: TimeZone = .current) -> String {
        var local = Calendar.current
        local.timeZone = localTimeZone
        var there = Calendar.current
        there.timeZone = timeZone
        let dayHere = local.dateComponents([.year, .month, .day], from: now)
        let dayThere = there.dateComponents([.year, .month, .day], from: now)
        let dayDiff = local.dateComponents([.day], from: local.date(from: dayHere)!, to: local.date(from: dayThere)!).day ?? 0
        let dayLabel = dayDiff > 0 ? String(localized: "Tomorrow")
            : dayDiff < 0 ? String(localized: "Yesterday") : String(localized: "Today")

        let seconds = timeZone.secondsFromGMT(for: now) - localTimeZone.secondsFromGMT(for: now)
        if seconds == 0 { return "\(dayLabel), \(String(localized: "same time"))" }
        let sign = seconds > 0 ? "+" : "−"
        let hours = abs(seconds) / 3600, minutes = (abs(seconds) % 3600) / 60
        let offset = minutes == 0 ? "\(sign)\(hours)h" : String(format: "%@%d:%02d", sign, hours, minutes)
        return "\(dayLabel), \(offset)"
    }

    nonisolated func formattedTime(at date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    nonisolated func iso8601String(at date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    nonisolated func isDaytime(at now: Date) -> Bool {
        var there = Calendar.current
        there.timeZone = timeZone
        return (6..<18).contains(there.component(.hour, from: now))
    }
}

/// Pure math for the Clock panel's Time Travel slider (±12h, 60-min steps normally or 15-min with ⌥).
enum TimeTravel {
    nonisolated static let rangeMinutes: ClosedRange<Int> = -720...720

    nonisolated static func clamp(_ minutes: Int) -> Int {
        min(max(minutes, rangeMinutes.lowerBound), rangeMinutes.upperBound)
    }

    nonisolated static func snap(_ rawMinutes: Double, fine: Bool) -> Int {
        let step = fine ? 15.0 : 60.0
        let snapped = Int((rawMinutes / step).rounded() * step)
        return clamp(snapped)
    }

    nonisolated static func targetDate(from now: Date, offsetMinutes: Int) -> Date {
        now.addingTimeInterval(TimeInterval(clamp(offsetMinutes) * 60))
    }

    /// e.g. "Now", "+3h", "−1h 30m", "+45m"
    nonisolated static func offsetLabel(minutes: Int) -> String {
        let clamped = clamp(minutes)
        guard clamped != 0 else { return String(localized: "Now") }
        let sign = clamped > 0 ? "+" : "−"
        let absM = abs(clamped)
        let h = absM / 60, m = absM % 60
        if h == 0 { return "\(sign)\(m)m" }
        if m == 0 { return "\(sign)\(h)h" }
        return "\(sign)\(h)h \(m)m"
    }
}

/// Calendar date helpers shared by `MonthCalendar`, `ClockFormatStyle`, and intents.
enum CalendarDateHelper {
    nonisolated static func weekNumber(for date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.weekOfYear, from: date)
    }

    nonisolated static func dayOfYear(for date: Date, calendar: Calendar = .current) -> Int {
        calendar.ordinality(of: .day, in: .year, for: date) ?? 1
    }

    /// e.g. "Today", "Tomorrow", "Yesterday", "in 4 days", "3 days ago"
    nonisolated static func relativeDayLabel(for date: Date, today: Date, calendar: Calendar = .current) -> String {
        let startToday = calendar.startOfDay(for: today)
        let startTarget = calendar.startOfDay(for: date)
        let diff = calendar.dateComponents([.day], from: startToday, to: startTarget).day ?? 0
        switch diff {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Tomorrow")
        case -1: return String(localized: "Yesterday")
        case 2...: return String(localized: "in \(diff) days")
        default: return String(localized: "\(-diff) days ago")
        }
    }

    /// Opens Apple Calendar at a specific date using `calshow://` (no Automation permission required).
    @MainActor
    static func openCalendarApp(at date: Date? = nil) {
        if let date, let url = URL(string: "calshow://\(Int(date.timeIntervalSinceReferenceDate))"),
           NSWorkspace.shared.open(url) {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }
}

/// Publishes the current time, waking once a second but only publishing when the visible text could change.
@Observable
@MainActor
final class ClockTicker {
    static let shared = ClockTicker()

    private(set) var now = Date()
    @ObservationIgnored private var timer: Timer?

    private init() {
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { ClockTicker.shared.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let date = Date()
        let clock = AppSettings.shared.clock
        let minuteChanged = Calendar.current.component(.minute, from: date) != Calendar.current.component(.minute, from: now)
        let needsSeconds = ClockFormat.showsSeconds(format: clock.format, showSeconds: clock.showSeconds,
                                                    customFormat: clock.customFormat)
        if needsSeconds || minuteChanged {
            now = date
        }
    }

    static func openCalendarApp(at date: Date? = nil) {
        CalendarDateHelper.openCalendarApp(at: date)
    }
}
