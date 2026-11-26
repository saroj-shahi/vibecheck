import AppKit
import EventKit
import Foundation
import Observation

extension Notification.Name {
    static let vibeCheckCalendarChanged = Notification.Name("VibeCheckCalendarChanged")
}

// MARK: - Plain Sendable models (what crosses from EventKit to @MainActor)

/// One calendar event copied out of EventKit (`EKEvent` is not `Sendable`).
struct CalendarEvent: Identifiable, Equatable, Sendable {
    /// Unique per occurrence (recurring events share `eventID` across dates).
    let id: String
    let eventID: String
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var calendarID: String
    var calendarTitle: String
    var red: Double
    var green: Double
    var blue: Double
    var location: String?
    var notes: String?
    var url: URL?
    var isRecurring: Bool
    var hasAlarms: Bool
    var isDeclined: Bool
    var attendeeNames: [String]
    var videoCall: VideoCallLink?

    nonisolated func isHappening(at now: Date) -> Bool {
        !isAllDay && now >= startDate && now < endDate
    }

    nonisolated func isPast(at now: Date) -> Bool {
        !isAllDay && endDate <= now
    }

    nonisolated func startsSoon(at now: Date, withinMinutes minutes: Int) -> Bool {
        !isAllDay && startDate > now && startDate.timeIntervalSince(now) <= TimeInterval(minutes * 60)
    }

    /// Every start-of-day date this event touches (handles multi-day events cleanly).
    nonisolated func spannedDays(calendar: Calendar = .current) -> [Date] {
        let first = calendar.startOfDay(for: startDate)
        // End dates on all-day or midnight-ending events belong to the previous day.
        let effectiveEnd = endDate > startDate ? endDate.addingTimeInterval(-1) : startDate
        let last = calendar.startOfDay(for: effectiveEnd)
        guard last >= first else { return [first] }
        var days: [Date] = []
        var cursor = first
        while cursor <= last && days.count < 62 {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }
}

/// One macOS calendar (`EKCalendar` for `.event`).
struct EventCalendar: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var source: String
    var red: Double
    var green: Double
    var blue: Double
    var isSubscribed: Bool
}

/// Whether VibeCheck may read Calendar events.
enum CalendarAccess: Equatable, Sendable {
    /// Never asked: prompted only when the user enables Calendar Events or clicks Connect Calendar.
    case notAsked
    case granted
    case denied
    case writeOnly
    case restricted

    nonisolated static func from(_ status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .notDetermined: .notAsked
        case .fullAccess: .granted
        case .writeOnly: .writeOnly
        case .restricted: .restricted
        case .denied: .denied
        @unknown default: .denied
        }
    }
}

// MARK: - Pure logic (unit-tested)

struct CalendarDayGroup: Identifiable, Equatable, Sendable {
    var id: Date { day }
    let day: Date
    let events: [CalendarEvent]
}

enum CalendarLogic {
    /// Collapses duplicate copies of the same event across synced accounts (same normalized title,
    /// start, end, and all-day flag), preferring the richest copy (video call > location/notes).
    nonisolated static func deduplicate(_ events: [CalendarEvent]) -> [CalendarEvent] {
        struct Key: Hashable {
            let title: String
            let start: Int
            let end: Int
            let allDay: Bool
        }
        func richness(_ e: CalendarEvent) -> Int {
            (e.videoCall != nil ? 4 : 0)
                + (e.location?.isEmpty == false ? 2 : 0)
                + (e.notes?.isEmpty == false ? 1 : 0)
                + (e.hasAlarms ? 1 : 0)
        }
        var bestIndexByKey: [Key: Int] = [:]
        var result: [CalendarEvent] = []
        result.reserveCapacity(events.count)
        for event in events {
            let key = Key(title: event.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                          start: Int(event.startDate.timeIntervalSince1970),
                          end: Int(event.endDate.timeIntervalSince1970),
                          allDay: event.isAllDay)
            if let existingIdx = bestIndexByKey[key] {
                if richness(event) > richness(result[existingIdx]) {
                    result[existingIdx] = event
                }
            } else {
                bestIndexByKey[key] = result.count
                result.append(event)
            }
        }
        return result
    }

    /// Filters events for agenda display.
    nonisolated static func filter(_ events: [CalendarEvent],
                                   hiddenCalendarIDs: Set<String>,
                                   showAllDay: Bool,
                                   hidePastToday: Bool,
                                   hideDeclined: Bool = true,
                                   now: Date,
                                   calendar: Calendar = .current) -> [CalendarEvent] {
        let todayStart = calendar.startOfDay(for: now)
        return events.filter { event in
            if hiddenCalendarIDs.contains(event.calendarID) { return false }
            if hideDeclined && event.isDeclined { return false }
            if !showAllDay && event.isAllDay { return false }
            if hidePastToday && !event.isAllDay && calendar.isDate(event.startDate, inSameDayAs: todayStart) && event.isPast(at: now) {
                return false
            }
            return true
        }
    }

    /// Groups events by start-of-day over `dayRange` (multi-day events appear on each day they span within the range).
    nonisolated static func groupByDay(_ events: [CalendarEvent],
                                       from startDay: Date,
                                       days: Int,
                                       calendar: Calendar = .current) -> [CalendarDayGroup] {
        let start = calendar.startOfDay(for: startDay)
        guard days > 0, let end = calendar.date(byAdding: .day, value: days, to: start) else { return [] }
        var buckets: [Date: [CalendarEvent]] = [:]
        for event in events {
            for day in event.spannedDays(calendar: calendar) where day >= start && day < end {
                buckets[day, default: []].append(event)
            }
        }
        return buckets.keys.sorted().map { day in
            let sorted = (buckets[day] ?? []).sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                if a.startDate != b.startDate { return a.startDate < b.startDate }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
            return CalendarDayGroup(day: day, events: sorted)
        }
    }

    /// Distinct calendar RGB tuples per start-of-day date (at most 3 dots per day for the month grid).
    nonisolated static func dotColors(for events: [CalendarEvent], calendar: Calendar = .current) -> [Date: [(Double, Double, Double)]] {
        var perDay: [Date: [(String, Double, Double, Double)]] = [:]
        for event in events {
            for day in event.spannedDays(calendar: calendar) {
                var list = perDay[day] ?? []
                if list.count < 3 && !list.contains(where: { $0.0 == event.calendarID }) {
                    list.append((event.calendarID, event.red, event.green, event.blue))
                    perDay[day] = list
                }
            }
        }
        return perDay.mapValues { $0.map { ($0.1, $0.2, $0.3) } }
    }

    /// Active video call or soonest video call starting within `lookaheadMinutes`.
    nonisolated static func nextJoinableCall(in events: [CalendarEvent],
                                             now: Date,
                                             hiddenCalendarIDs: Set<String> = [],
                                             lookaheadMinutes: Int = 15) -> CalendarEvent? {
        let candidates = events.filter { event in
            !event.isAllDay && !event.isDeclined
                && !hiddenCalendarIDs.contains(event.calendarID)
                && event.videoCall != nil
                && (event.isHappening(at: now) || event.startsSoon(at: now, withinMinutes: lookaheadMinutes))
        }
        // Prefer an upcoming call starting very soon (<= 5m) over an almost-finished call, otherwise soonest start.
        return candidates.min { a, b in
            let aStartingSoon = a.startsSoon(at: now, withinMinutes: 5)
            let bStartingSoon = b.startsSoon(at: now, withinMinutes: 5)
            if aStartingSoon != bStartingSoon { return aStartingSoon }
            return a.startDate < b.startDate
        }
    }

    /// Next event eligible for menu bar or tile summary.
    nonisolated static func nextEvent(in events: [CalendarEvent],
                                      now: Date,
                                      hiddenCalendarIDs: Set<String> = [],
                                      onlyVideoCalls: Bool = false,
                                      showDuringEntireEvent: Bool = true,
                                      lookaheadMinutes: Int = 240) -> CalendarEvent? {
        let horizon = now.addingTimeInterval(TimeInterval(lookaheadMinutes * 60))
        let candidates = events.filter { event in
            guard !event.isAllDay, !event.isDeclined, !hiddenCalendarIDs.contains(event.calendarID) else { return false }
            if onlyVideoCalls && event.videoCall == nil { return false }
            if event.isHappening(at: now) { return showDuringEntireEvent }
            return event.startDate > now && event.startDate <= horizon
        }
        return candidates.min { a, b in
            // If an upcoming event starts within 5 min, show it ahead of a currently running event.
            let aImminent = a.startsSoon(at: now, withinMinutes: 5)
            let bImminent = b.startsSoon(at: now, withinMinutes: 5)
            if aImminent != bImminent { return aImminent }
            if a.isHappening(at: now) != b.isHappening(at: now) { return a.isHappening(at: now) }
            return a.startDate < b.startDate
        }
    }

    /// Short countdown label: "now", "in 8m", "in 1h 20m", or "12m left" while happening.
    nonisolated static func countdownText(for event: CalendarEvent, now: Date) -> String {
        if event.isHappening(at: now) {
            let remaining = max(1, Int(ceil(event.endDate.timeIntervalSince(now) / 60)))
            return formatMinutes(remaining) + " " + String(localized: "left")
        }
        let until = event.startDate.timeIntervalSince(now)
        if until <= 45 { return String(localized: "now") }
        let mins = Int(ceil(until / 60))
        return String(localized: "in \(formatMinutes(mins))")
    }

    /// Compact countdown for tight slots ("8m", "1h 20m", "now", "12m left").
    nonisolated static func compactCountdown(for event: CalendarEvent, now: Date) -> String {
        if event.isHappening(at: now) {
            let remaining = max(1, Int(ceil(event.endDate.timeIntervalSince(now) / 60)))
            return "\(formatMinutes(remaining)) left"
        }
        let until = event.startDate.timeIntervalSince(now)
        if until <= 45 { return String(localized: "now") }
        return formatMinutes(Int(ceil(until / 60)))
    }

    private nonisolated static func formatMinutes(_ total: Int) -> String {
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// Day header title: "Today", "Tomorrow", "Yesterday", or "Thu, 28 Nov".
    nonisolated static func dayHeader(_ day: Date, today: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: today) { return String(localized: "Today") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), calendar.isDate(day, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), calendar.isDate(day, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

// MARK: - Store

/// Opt-in Apple Calendar store backed by EventKit.
/// Mirrors `RemindersStore`: never prompts at launch or from menu bar labels; prompts only when the user
/// enables Calendar Events or clicks Connect Calendar. Zero polling: refreshes on `.EKEventStoreChanged`
/// and once at midnight.
@Observable
@MainActor
final class CalendarStore {
    static let shared = CalendarStore()

    private(set) var access: CalendarAccess = .notAsked
    private(set) var calendars: [EventCalendar] = []
    /// Deduplicated events across the loaded window (default −7d…+45d).
    private(set) var events: [CalendarEvent] = []
    private(set) var loaded = false

    @ObservationIgnored private var store: EKEventStore?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var midnightTimer: Timer?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var requesting = false
    @ObservationIgnored private var generation = 0
    /// Extra month window requested when browsing distant months in `MonthCalendar`.
    @ObservationIgnored private var extraWindow: DateInterval?

    private init() {}

    /// Picks up existing access once, without ever prompting. Safe to call from a view `.task`.
    func ensureStarted() {
        guard !started else { return }
        started = true
        Task { @MainActor in self.activate(requestAccess: false) }
    }

    /// Reads current Calendar permission; requests full access only when `requestAccess == true`.
    func activate(requestAccess: Bool) {
        started = true
        guard !RemindersStore.isTestProcess else { return }
        let status = CalendarAccess.from(EKEventStore.authorizationStatus(for: .event))
        if status == .granted {
            access = .granted
            startObserving()
            scheduleMidnightRefresh()
            reload()
            return
        }
        access = status
        guard status == .notAsked, requestAccess, !requesting else { return }
        requesting = true
        let asking = EKEventStore()
        Self.requestFullAccess(asking) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.requesting = false
                self.store = nil
                self.activate(requestAccess: false)
                if !granted { self.access = CalendarAccess.from(EKEventStore.authorizationStatus(for: .event)) }
            }
        }
    }

    /// Ensures events covering `month` are loaded when the user browses beyond the default window.
    func ensureMonthLoaded(_ month: Date) {
        guard access == .granted else { return }
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: month) else { return }
        let now = Date()
        let defaultStart = cal.date(byAdding: .day, value: -7, to: now) ?? now
        let defaultEnd = cal.date(byAdding: .day, value: 45, to: now) ?? now
        if interval.start >= defaultStart && interval.end <= defaultEnd { return }
        if let existing = extraWindow, existing.contains(interval.start), existing.contains(interval.end) { return }
        extraWindow = interval
        reload()
    }

    func reload() {
        guard !RemindersStore.isTestProcess else { return }
        let status = CalendarAccess.from(EKEventStore.authorizationStatus(for: .event))
        guard status == .granted else { access = status; return }
        access = .granted
        let store = eventStore()
        calendars = store.calendars(for: .event)
            .map(Self.calendarInfo(from:))
            .sorted {
                if $0.source != $1.source { return $0.source.localizedStandardCompare($1.source) == .orderedAscending }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }

        let now = Date()
        let cal = Calendar.current
        var start = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now)) ?? now
        var end = cal.date(byAdding: .day, value: 45, to: cal.startOfDay(for: now)) ?? now
        if let extra = extraWindow {
            start = min(start, extra.start)
            end = max(end, extra.end)
        }

        generation += 1
        let current = generation
        let fetched = Self.fetchEvents(store, start: start, end: end)
        guard generation == current else { return }
        events = CalendarLogic.deduplicate(fetched)
        loaded = true
        NotificationCenter.default.post(name: .vibeCheckCalendarChanged, object: nil)
    }

    /// Joins the active or next video call starting within `lookaheadMinutes`, returning the joined event if any.
    @discardableResult
    func joinNextVideoCall(lookaheadMinutes: Int = 15) -> CalendarEvent? {
        let hidden = AppSettings.shared.clock.hiddenCalendarIDs
        guard let event = CalendarLogic.nextJoinableCall(in: events, now: Date(),
                                                         hiddenCalendarIDs: hidden,
                                                         lookaheadMinutes: lookaheadMinutes),
              let link = event.videoCall else { return nil }
        NSWorkspace.shared.open(link.url)
        return event
    }

    /// System Settings › Privacy & Security › Calendars.
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Private

    private func eventStore() -> EKEventStore {
        if let store { return store }
        let made = EKEventStore()
        store = made
        return made
    }

    private func startObserving() {
        guard observer == nil else { return }
        let store = eventStore()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.access == .granted else { return }
                self.reload()
            }
        }
    }

    private func scheduleMidnightRefresh() {
        midnightTimer?.invalidate()
        let cal = Calendar.current
        guard let nextMidnight = cal.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 5), matchingPolicy: .nextTime) else { return }
        let interval = max(60, nextMidnight.timeIntervalSinceNow)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
                self?.scheduleMidnightRefresh()
            }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }

    private static func calendarInfo(from ek: EKCalendar) -> EventCalendar {
        var item = EventCalendar(id: ek.calendarIdentifier, title: ek.title,
                                 source: ek.source?.title ?? "",
                                 red: 0.36, green: 0.6, blue: 1.0,
                                 isSubscribed: ek.type == .subscription)
        if let color = NSColor(cgColor: ek.cgColor)?.usingColorSpace(.sRGB) {
            item.red = Double(color.redComponent)
            item.green = Double(color.greenComponent)
            item.blue = Double(color.blueComponent)
        }
        return item
    }

    private static func fetchEvents(_ store: EKEventStore, start: Date, end: Date) -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap { ek -> CalendarEvent? in
            guard let startDate = ek.startDate, let endDate = ek.endDate else { return nil }
            var r = 0.36, g = 0.6, b = 1.0
            if let cg = ek.calendar?.cgColor, let color = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) {
                r = Double(color.redComponent)
                g = Double(color.greenComponent)
                b = Double(color.blueComponent)
            }
            let title = (ek.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let declined = ek.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
            let attendeeNames = (ek.attendees ?? [])
                .filter { !$0.isCurrentUser }
                .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let videoCall = VideoCallDetector.detect(url: ek.url, location: ek.location, notes: ek.notes)
            let eventID = ek.eventIdentifier ?? UUID().uuidString
            let occID = "\(eventID)|\(Int(startDate.timeIntervalSince1970))"
            return CalendarEvent(
                id: occID,
                eventID: eventID,
                title: title.isEmpty ? String(localized: "Untitled event") : title,
                startDate: startDate,
                endDate: endDate,
                isAllDay: ek.isAllDay,
                calendarID: ek.calendar?.calendarIdentifier ?? "",
                calendarTitle: ek.calendar?.title ?? "",
                red: r, green: g, blue: b,
                location: ek.location,
                notes: ek.notes,
                url: ek.url,
                isRecurring: ek.hasRecurrenceRules,
                hasAlarms: ek.hasAlarms,
                isDeclined: declined,
                attendeeNames: attendeeNames,
                videoCall: videoCall
            )
        }
    }

    nonisolated private static func requestFullAccess(_ store: EKEventStore, completion: @escaping @Sendable (Bool) -> Void) {
        store.requestFullAccessToEvents { granted, _ in completion(granted) }
    }
}
