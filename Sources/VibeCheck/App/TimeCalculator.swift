import Foundation

/// One computed date/time answer shown inline in the ⌘K command palette.
struct TimeCalcResult: Equatable, Sendable {
    let title: String
    let copyValue: String
    let subtitle: String
}

/// Pure, offline date and time calculator for the ⌘K palette.
/// Handles:
/// - Time zone conversions: `3pm EST`, `14:30 UTC`, `9:15am PST`, `10am Tokyo`
/// - Relative offsets: `now + 3h30m`, `today + 45d`, `today - 2w`, `+90 days`
/// - Date differences: `days until Dec 31`, `weeks until 2027-01-01`, `days since 2026-01-01`
enum TimeCalculator {
    nonisolated static func evaluate(_ raw: String,
                                     now: Date = Date(),
                                     localTimeZone: TimeZone = .current,
                                     calendar baseCalendar: Calendar = .current) -> TimeCalcResult? {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return nil }
        var cal = baseCalendar
        cal.timeZone = localTimeZone

        if let res = evaluateDurationUntilOrSince(q, now: now, calendar: cal) { return res }
        if let res = evaluateRelativeOffset(q, now: now, calendar: cal) { return res }
        if let res = evaluateTimeZoneConversion(q, now: now, localTimeZone: localTimeZone, calendar: cal) { return res }
        return nil
    }

    // MARK: - 1. Time zone conversion ("3pm EST", "14:30 UTC", "10:15 am Tokyo")

    private nonisolated static func evaluateTimeZoneConversion(_ q: String, now: Date, localTimeZone: TimeZone, calendar: Calendar) -> TimeCalcResult? {
        let pattern = #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s+(?:in\s+)?([A-Za-z][A-Za-z0-9_/\-\s]{1,28})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)),
              let hourRange = Range(match.range(at: 1), in: q),
              let zoneRange = Range(match.range(at: 4), in: q),
              var hour = Int(q[hourRange]) else { return nil }

        let minute: Int = Range(match.range(at: 2), in: q).flatMap { Int(q[$0]) } ?? 0
        let ampm = Range(match.range(at: 3), in: q).map { q[$0].lowercased() }
        guard minute >= 0 && minute < 60 else { return nil }

        if let ampm {
            guard hour >= 1 && hour <= 12 else { return nil }
            if ampm == "pm" && hour != 12 { hour += 12 }
            if ampm == "am" && hour == 12 { hour = 0 }
        } else {
            // Require either `:mm` or 24-hour value so bare words like "2 days" don't accidentally match.
            guard match.range(at: 2).location != NSNotFound, hour >= 0 && hour <= 23 else { return nil }
        }

        let zoneToken = String(q[zoneRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolved = resolveTimeZone(zoneToken) else { return nil }

        var sourceCal = calendar
        sourceCal.timeZone = resolved.timeZone
        var comps = sourceCal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        guard let instant = sourceCal.date(from: comps) else { return nil }

        let localText = instant.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: localTimeZone))
        let sourceText = instant.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: resolved.timeZone))

        let localDay = calendar.startOfDay(for: instant)
        let todayStart = calendar.startOfDay(for: now)
        let dayDiff = calendar.dateComponents([.day], from: todayStart, to: localDay).day ?? 0
        let daySuffix = dayDiff > 0 ? " (\(String(localized: "tomorrow")))"
            : dayDiff < 0 ? " (\(String(localized: "yesterday")))" : ""

        let answer = "\(localText)\(daySuffix)"
        return TimeCalcResult(
            title: "\(sourceText) \(resolved.label) → \(answer)",
            copyValue: answer,
            subtitle: String(localized: "Local time · press ↩ to copy")
        )
    }

    private nonisolated static func resolveTimeZone(_ token: String) -> (timeZone: TimeZone, label: String)? {
        let upper = token.uppercased()
        let fixedOffsets: [String: (String, String)] = [
            "UTC": ("UTC", "UTC"),
            "GMT": ("GMT", "GMT"),
            "EST": ("America/New_York", "EST"),
            "EDT": ("America/New_York", "EDT"),
            "ET": ("America/New_York", "ET"),
            "CST": ("America/Chicago", "CST"),
            "CDT": ("America/Chicago", "CDT"),
            "CT": ("America/Chicago", "CT"),
            "MST": ("America/Denver", "MST"),
            "MDT": ("America/Denver", "MDT"),
            "MT": ("America/Denver", "MT"),
            "PST": ("America/Los_Angeles", "PST"),
            "PDT": ("America/Los_Angeles", "PDT"),
            "PT": ("America/Los_Angeles", "PT"),
            "BST": ("Europe/London", "BST"),
            "CET": ("Europe/Berlin", "CET"),
            "CEST": ("Europe/Berlin", "CEST"),
            "IST": ("Asia/Kolkata", "IST"),
            "NPT": ("Asia/Kathmandu", "NPT"),
            "JST": ("Asia/Tokyo", "JST"),
            "KST": ("Asia/Seoul", "KST"),
            "SGT": ("Asia/Singapore", "SGT"),
            "HKT": ("Asia/Hong_Kong", "HKT"),
            "AEST": ("Australia/Sydney", "AEST"),
            "AEDT": ("Australia/Sydney", "AEDT"),
            "NZST": ("Pacific/Auckland", "NZST"),
            "NZDT": ("Pacific/Auckland", "NZDT"),
        ]
        if let (tzID, label) = fixedOffsets[upper], let tz = TimeZone(identifier: tzID) {
            return (tz, label)
        }
        if let tz = TimeZone(identifier: token) {
            return (tz, WorldClock.cityName(token))
        }
        // Check offline city index for exact city name / alias match (e.g. "Tokyo", "London", "SF").
        if let city = CityIndex.search(token, limit: 1).first,
           city.name.lowercased() == token.lowercased() || city.aliases.contains(where: { $0.lowercased() == token.lowercased() }),
           let tz = TimeZone(identifier: city.timeZoneID) {
            return (tz, city.name)
        }
        return nil
    }

    // MARK: - 2. Relative offset ("now + 3h30m", "today + 45d", "+90 days", "today - 2w")

    private nonisolated static func evaluateRelativeOffset(_ q: String, now: Date, calendar: Calendar) -> TimeCalcResult? {
        let pattern = #"^(?:(now|today)\s*)?([+-])\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)),
              let signRange = Range(match.range(at: 2), in: q),
              let bodyRange = Range(match.range(at: 3), in: q) else { return nil }

        let anchor = Range(match.range(at: 1), in: q).map { q[$0].lowercased() } ?? ""
        let sign = q[signRange] == "-" ? -1 : 1
        let body = String(q[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        let termPattern = #"(\d+)\s*(years?|yrs?|y|months?|mos?|weeks?|wks?|w|days?|d|hours?|hrs?|h|minutes?|mins?|m)(?=\s|$|\d)"#
        guard let termRegex = try? NSRegularExpression(pattern: termPattern, options: .caseInsensitive) else { return nil }
        let matches = termRegex.matches(in: body, range: NSRange(body.startIndex..., in: body))
        guard !matches.isEmpty else { return nil }

        // Ensure no stray unmatched words remain in `body`.
        let stripped = termRegex.stringByReplacingMatches(in: body, range: NSRange(body.startIndex..., in: body), withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard stripped.isEmpty else { return nil }

        var comps = DateComponents()
        var hasTimeUnit = false
        for m in matches {
            guard let nRange = Range(m.range(at: 1), in: body),
                  let uRange = Range(m.range(at: 2), in: body),
                  let n = Int(body[nRange]) else { return nil }
            let val = n * sign
            switch body[uRange].lowercased() {
            case "y", "yr", "yrs", "year", "years": comps.year = (comps.year ?? 0) + val
            case "mo", "mos", "month", "months": comps.month = (comps.month ?? 0) + val
            case "w", "wk", "wks", "week", "weeks": comps.day = (comps.day ?? 0) + val * 7
            case "d", "day", "days": comps.day = (comps.day ?? 0) + val
            case "h", "hr", "hrs", "hour", "hours": comps.hour = (comps.hour ?? 0) + val; hasTimeUnit = true
            case "m", "min", "mins", "minute", "minutes": comps.minute = (comps.minute ?? 0) + val; hasTimeUnit = true
            default: return nil
            }
        }

        let base = (anchor == "today" && !hasTimeUnit) ? calendar.startOfDay(for: now) : now
        guard let target = calendar.date(byAdding: comps, to: base) else { return nil }

        let formatted: String
        if hasTimeUnit {
            formatted = target.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: calendar.timeZone))
        } else {
            formatted = target.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).day().month(.abbreviated).year())
        }
        return TimeCalcResult(
            title: "= \(formatted)",
            copyValue: formatted,
            subtitle: String(localized: "Week \(CalendarDateHelper.weekNumber(for: target, calendar: calendar)) · press ↩ to copy")
        )
    }

    // MARK: - 3. Duration until / since ("days until Dec 31", "weeks until 2027-01-01")

    private nonisolated static func evaluateDurationUntilOrSince(_ q: String, now: Date, calendar: Calendar) -> TimeCalcResult? {
        let pattern = #"^(days|weeks)\s+(until|to|since)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)),
              let unitRange = Range(match.range(at: 1), in: q),
              let prepRange = Range(match.range(at: 2), in: q),
              let dateRange = Range(match.range(at: 3), in: q) else { return nil }

        let unit = q[unitRange].lowercased()
        let prep = q[prepRange].lowercased()
        let rawDate = String(q[dateRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target = parseDate(rawDate, now: now, preferFuture: prep != "since", calendar: calendar) else { return nil }

        let startToday = calendar.startOfDay(for: now)
        let startTarget = calendar.startOfDay(for: target)
        let signedDays = calendar.dateComponents([.day], from: startToday, to: startTarget).day ?? 0
        let diffDays = prep == "since" ? -signedDays : signedDays

        let targetLabel = startTarget.formatted(Date.FormatStyle(timeZone: calendar.timeZone).day().month(.abbreviated).year())
        if unit == "weeks" {
            let weeks = diffDays / 7
            let rem = abs(diffDays % 7)
            let answer = rem == 0 ? "\(weeks) weeks" : "\(weeks)w \(rem)d (\(diffDays) days)"
            return TimeCalcResult(
                title: "\(answer) \(prep) \(targetLabel)",
                copyValue: answer,
                subtitle: String(localized: "Press ↩ to copy")
            )
        } else {
            let answer = diffDays == 1 ? "1 day" : "\(diffDays) days"
            return TimeCalcResult(
                title: "\(answer) \(prep) \(targetLabel)",
                copyValue: answer,
                subtitle: String(localized: "Press ↩ to copy")
            )
        }
    }

    private nonisolated static func parseDate(_ raw: String, now: Date, preferFuture: Bool, calendar: Calendar) -> Date? {
        let formatsWithYear = ["yyyy-MM-dd", "MMM d yyyy", "MMM d, yyyy", "d MMM yyyy", "MMMM d yyyy", "MMMM d, yyyy", "MM/dd/yyyy"]
        for f in formatsWithYear {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = calendar.timeZone
            df.dateFormat = f
            if let d = df.date(from: raw) { return d }
        }
        // Month + day without year (e.g. "Dec 31" or "25 Dec"): pick current year, or next/prev year if needed.
        let year = calendar.component(.year, from: now)
        let formatsNoYear = ["MMM d", "d MMM", "MMMM d", "d MMMM"]
        for f in formatsNoYear {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = calendar.timeZone
            df.dateFormat = "\(f) yyyy"
            if let candidate = df.date(from: "\(raw) \(year)") {
                let startToday = calendar.startOfDay(for: now)
                if preferFuture && candidate < startToday, let nextYear = calendar.date(byAdding: .year, value: 1, to: candidate) {
                    return nextYear
                }
                if !preferFuture && candidate > startToday, let prevYear = calendar.date(byAdding: .year, value: -1, to: candidate) {
                    return prevYear
                }
                return candidate
            }
        }
        return nil
    }
}
