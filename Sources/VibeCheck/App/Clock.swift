import AppKit
import Foundation
import Observation

/// Menu bar clock formats. Templates adapt to the user's locale (12/24-hour, day/month order).
enum ClockFormat: String, CaseIterable, Identifiable, Codable {
    case time, dayTime, dateTime, time24

    var id: String { rawValue }

    func template(seconds: Bool) -> String {
        let s = seconds ? "ss" : ""
        switch self {
        case .time: return "jmm\(s)"
        case .dayTime: return "EEEjmm\(s)"
        case .dateTime: return "EEEdMMMjmm\(s)"
        case .time24: return "HHmm\(s)"
        }
    }

    func formatter(seconds: Bool) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(template(seconds: seconds))
        return formatter
    }
}

/// Format style used by SwiftUI `Text(date, format:)`.
struct ClockFormatStyle: FormatStyle {
    let format: ClockFormat
    let seconds: Bool

    func format(_ value: Date) -> String {
        Self.cache(format, seconds).string(from: value)
    }

    private static func cache(_ format: ClockFormat, _ seconds: Bool) -> DateFormatter {
        // DateFormatter is expensive to create; reuse one per format.
        let key = "\(format.rawValue)-\(seconds)"
        if let cached = formatters[key] { return cached }
        let made = format.formatter(seconds: seconds)
        formatters[key] = made
        return made
    }

    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]
}

struct WorldClock: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var timeZoneID: String

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .gmt }

    static let defaults = [
        WorldClock(name: "UTC", timeZoneID: "UTC"),
        WorldClock(name: "London", timeZoneID: "Europe/London"),
        WorldClock(name: "New York", timeZoneID: "America/New_York"),
    ]

    /// "America/New_York" → "New York"
    static func cityName(_ identifier: String) -> String {
        (identifier.split(separator: "/").last.map(String.init) ?? identifier).replacingOccurrences(of: "_", with: " ")
    }

    /// e.g. "Today, +5:45", "Tomorrow, +10", "Same time"
    func relativeDescription(at now: Date) -> String {
        let local = Calendar.current
        var there = Calendar.current
        there.timeZone = timeZone
        let dayHere = local.dateComponents([.year, .month, .day], from: now)
        let dayThere = there.dateComponents([.year, .month, .day], from: now)
        let dayDiff = local.dateComponents([.day], from: local.date(from: dayHere)!, to: local.date(from: dayThere)!).day ?? 0
        let dayLabel = dayDiff > 0 ? "Tomorrow" : dayDiff < 0 ? "Yesterday" : "Today"

        let seconds = timeZone.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)
        if seconds == 0 { return "\(dayLabel), same time" }
        let sign = seconds > 0 ? "+" : "−"
        let hours = abs(seconds) / 3600, minutes = (abs(seconds) % 3600) / 60
        let offset = minutes == 0 ? "\(sign)\(hours)h" : String(format: "%@%d:%02d", sign, hours, minutes)
        return "\(dayLabel), \(offset)"
    }

    func isDaytime(at now: Date) -> Bool {
        var there = Calendar.current
        there.timeZone = timeZone
        return (6..<18).contains(there.component(.hour, from: now))
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
        let minuteChanged = Calendar.current.component(.minute, from: date) != Calendar.current.component(.minute, from: now)
        if AppSettings.shared.clockShowSeconds || minuteChanged || AppSettings.shared.isClockPanelOpen {
            now = date
        }
    }

    static func openCalendarApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }
}
