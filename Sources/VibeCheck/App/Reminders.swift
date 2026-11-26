import AppKit
import EventKit
import Foundation
import Observation

// MARK: - Plain values (what crosses from EventKit's queue to the main actor)

/// One reminder, copied out of EventKit: `EKReminder` isn't Sendable, so nothing else leaves the fetch.
struct TodoItem: Identifiable, Equatable, Sendable {
    /// `calendarItemIdentifier`.
    let id: String
    var title: String
    var due: Date?
    /// The reminder has a time of day, not just a date.
    var dueHasTime = false
    var completed = false
    var completionDate: Date?
    var created: Date?
}

/// A Reminders list (an `EKCalendar` for reminders).
struct TodoList: Identifiable, Equatable, Sendable {
    /// `calendarIdentifier`.
    let id: String
    var title: String
    /// sRGB components of the list's color.
    var red = 0.5, green = 0.5, blue = 0.5
}

/// Whether VibeCheck may read Reminders.
enum TodoAccess: Equatable, Sendable {
    /// Never asked: the prompt comes when the module is turned on or its panel opens.
    case notAsked
    case granted
    case denied
    /// Add-only access: VibeCheck can't show the list, so it's treated like denied.
    case writeOnly
    case restricted

    nonisolated static func from(_ status: EKAuthorizationStatus) -> TodoAccess {
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

/// Where a reminder's due date falls; the open list is sorted in this order.
enum TodoDue: Int, Comparable, Sendable {
    case overdue, today, none, later
    static func < (a: TodoDue, b: TodoDue) -> Bool { a.rawValue < b.rawValue }
}

// MARK: - Pure logic (tested)

enum TodoLogic {
    /// Completed tasks shown under "Completed".
    nonisolated static let completedLimit = 10
    /// How far back completed tasks are fetched.
    nonisolated static let completedDays = 7

    /// Due date from a reminder's components; `hasTime` when they carry an hour.
    nonisolated static func due(from components: DateComponents?, calendar: Calendar = .current) -> (date: Date, hasTime: Bool)? {
        guard let components, components.year != nil, components.month != nil, components.day != nil else { return nil }
        var parts = components
        let cal = parts.calendar ?? calendar
        parts.calendar = cal
        if parts.timeZone == nil { parts.timeZone = cal.timeZone }
        guard let date = cal.date(from: parts) else { return nil }
        return (date, components.hour != nil)
    }

    /// Builds the plain item from the values read off an `EKReminder`.
    nonisolated static func item(id: String, title: String?, dueComponents: DateComponents?, completed: Bool,
                                 completionDate: Date?, created: Date?, calendar: Calendar = .current) -> TodoItem {
        let due = due(from: dueComponents, calendar: calendar)
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return TodoItem(id: id, title: trimmed.isEmpty ? String(localized: "Untitled") : trimmed,
                        due: due?.date, dueHasTime: due?.hasTime ?? false, completed: completed,
                        completionDate: completed ? completionDate : nil, created: created)
    }

    /// Overdue: a timed reminder past its time, or a date-only one from an earlier day.
    nonisolated static func bucket(_ item: TodoItem, now: Date, calendar: Calendar = .current) -> TodoDue {
        guard let due = item.due else { return .none }
        if item.dueHasTime ? due < now : calendar.startOfDay(for: due) < calendar.startOfDay(for: now) { return .overdue }
        return calendar.isDate(due, inSameDayAs: now) ? .today : .later
    }

    /// Overdue → due today → no date → later. Dated groups go by due date; undated ones newest first.
    nonisolated static func sortOpen(_ items: [TodoItem], now: Date, calendar: Calendar = .current) -> [TodoItem] {
        items.filter { !$0.completed }
            .map { (bucket($0, now: now, calendar: calendar), $0) }
            .sorted { a, b in
                if a.0 != b.0 { return a.0 < b.0 }
                if let da = a.1.due, let db = b.1.due, da != db { return da < db }
                if a.0 == .none, a.1.created != b.1.created {
                    return (a.1.created ?? .distantPast) > (b.1.created ?? .distantPast)
                }
                return a.1.title.localizedStandardCompare(b.1.title) == .orderedAscending
            }
            .map(\.1)
    }

    /// The most recently completed tasks, newest first.
    nonisolated static func recentCompleted(_ items: [TodoItem], limit: Int = completedLimit) -> [TodoItem] {
        Array(items.filter(\.completed)
            .sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
            .prefix(max(0, limit)))
    }

    /// Open count for the menu bar: three characters at most, so the item's measured width holds.
    nonisolated static func countLabel(_ count: Int) -> String {
        count > 99 ? "99+" : String(max(0, count))
    }

    /// Tasks overdue or due today (drawn in the accent color).
    nonisolated static func dueNowCount(_ items: [TodoItem], now: Date, calendar: Calendar = .current) -> Int {
        items.filter { !$0.completed && bucket($0, now: now, calendar: calendar) <= .today }.count
    }

    /// The chosen list, else the default list, else the first one.
    nonisolated static func resolveList(id: String, lists: [TodoList], defaultID: String?) -> TodoList? {
        lists.first { $0.id == id } ?? lists.first { $0.id == defaultID } ?? lists.first
    }

    /// Short due text: "Today", "Today 3:00 PM", "Yesterday", "Tomorrow", else the date.
    nonisolated static func dueText(_ item: TodoItem, now: Date, calendar: Calendar = .current) -> String? {
        guard let due = item.due else { return nil }
        let time = item.dueHasTime ? " " + due.formatted(date: .omitted, time: .shortened) : ""
        if calendar.isDate(due, inSameDayAs: now) { return String(localized: "Today") + time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(due, inSameDayAs: yesterday) {
            return String(localized: "Yesterday") + time
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow") + time
        }
        return due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + time
    }
}

// MARK: - Store

/// The To-do module's view of Apple Reminders: one list, open tasks and the last week's completed ones.
/// Access is only asked for when the module is turned on or its panel opens, never at launch. Refreshes on
/// `.EKEventStoreChanged` (no polling); fetches run on EventKit's own queue and publish here on the main actor.
@Observable
@MainActor
final class RemindersStore {
    static let shared = RemindersStore()

    private(set) var access: TodoAccess = .notAsked
    private(set) var lists: [TodoList] = []
    private(set) var defaultListID: String?
    /// Sorted open tasks of the chosen list.
    private(set) var open: [TodoItem] = []
    /// Recently completed tasks, newest first (at most `TodoLogic.completedLimit`).
    private(set) var completed: [TodoItem] = []
    /// The first fetch after access was granted has come back.
    private(set) var loaded = false
    private(set) var errorMessage: String?
    /// Set by ⌘K "Add task…": the panel focuses its field and clears this.
    var wantsAddFocus = false

    @ObservationIgnored private var store: EKEventStore?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored private var requesting = false

    private init() {}

    /// Running under `swift test` (the test bundle is loaded): the store stays empty and never asks.
    nonisolated static let isTestProcess = Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
        || ["xctest", "swiftpm-testing-helper"].contains(ProcessInfo.processInfo.processName)

    var selectedList: TodoList? {
        TodoLogic.resolveList(id: AppSettings.shared.todo.listID, lists: lists, defaultID: defaultListID)
    }

    var dueNowCount: Int { TodoLogic.dueNowCount(open, now: Date()) }

    /// From views (label, tile): picks up existing access once, without ever prompting. Safe in a body.
    func ensureStarted() {
        guard !started else { return }
        started = true
        Task { @MainActor in self.activate(requestAccess: false) }
    }

    /// Reads the current permission; asks for it only when `requestAccess` (module turned on, panel opened).
    func activate(requestAccess: Bool) {
        started = true
        guard !Self.isTestProcess else { return }   // tests never touch the real Reminders store
        let status = TodoAccess.from(EKEventStore.authorizationStatus(for: .reminder))
        if status == .granted {
            access = .granted
            startObserving()
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
                // A fresh store after the grant: one made before it may keep seeing nothing.
                self.store = nil
                self.activate(requestAccess: false)
                if !granted { self.access = TodoAccess.from(EKEventStore.authorizationStatus(for: .reminder)) }
            }
        }
    }

    /// Fetches lists, open tasks and the last week's completed tasks of the chosen list.
    func reload() {
        guard !Self.isTestProcess else { return }
        let status = TodoAccess.from(EKEventStore.authorizationStatus(for: .reminder))
        guard status == .granted else { access = status; return }
        access = .granted
        let store = eventStore()
        lists = store.calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .map(Self.list(from:))
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        defaultListID = store.defaultCalendarForNewReminders()?.calendarIdentifier
        guard let list = selectedList, let calendar = store.calendar(withIdentifier: list.id) else {
            open = []; completed = []; loaded = true
            return
        }
        generation += 1
        let current = generation
        let since = Calendar.current.date(byAdding: .day, value: -TodoLogic.completedDays, to: Date())
        let openPredicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [calendar])
        let donePredicate = store.predicateForCompletedReminders(withCompletionDateStarting: since, ending: nil, calendars: [calendar])
        Self.fetch(store, openPredicate) { [weak self] items in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.open = TodoLogic.sortOpen(items, now: Date())
                self.loaded = true
            }
        }
        Self.fetch(store, donePredicate) { [weak self] items in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.completed = TodoLogic.recentCompleted(items)
            }
        }
    }

    // MARK: Editing

    func add(title: String, due: Date? = nil) {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, access == .granted else { return }
        let store = eventStore()
        guard let list = selectedList, let calendar = store.calendar(withIdentifier: list.id) else {
            errorMessage = String(localized: "Pick a Reminders list in Settings first.")
            return
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = text
        reminder.calendar = calendar
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: due)
        }
        do {
            try store.save(reminder, commit: true)
            errorMessage = nil
            let item = TodoItem(id: reminder.calendarItemIdentifier, title: text, due: due, dueHasTime: false, created: Date())
            open = TodoLogic.sortOpen(open + [item], now: Date())
        } catch {
            errorMessage = String(localized: "Couldn't add that to Reminders.")
        }
    }

    func setCompleted(_ item: TodoItem, _ done: Bool) {
        guard let reminder = reminder(item.id) else { return reload() }
        reminder.isCompleted = done
        do {
            try eventStore().save(reminder, commit: true)
            errorMessage = nil
            var changed = item
            changed.completed = done
            changed.completionDate = done ? Date() : nil
            open.removeAll { $0.id == item.id }
            completed.removeAll { $0.id == item.id }
            if done {
                completed = TodoLogic.recentCompleted([changed] + completed)
            } else {
                open = TodoLogic.sortOpen(open + [changed], now: Date())
            }
        } catch {
            errorMessage = String(localized: "Couldn't update that reminder.")
        }
    }

    func delete(_ item: TodoItem) {
        guard let reminder = reminder(item.id) else { return reload() }
        do {
            try eventStore().remove(reminder, commit: true)
            errorMessage = nil
            open.removeAll { $0.id == item.id }
            completed.removeAll { $0.id == item.id }
        } catch {
            errorMessage = String(localized: "Couldn't delete that reminder.")
        }
    }

    /// System Settings › Privacy & Security › Reminders.
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
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

    private func reminder(_ id: String) -> EKReminder? {
        guard access == .granted else { return nil }
        return eventStore().calendarItem(withIdentifier: id) as? EKReminder
    }

    private func startObserving() {
        guard observer == nil else { return }
        let store = eventStore()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AppSettings.shared.isEnabled(.todo) else { return }
                self.reload()
            }
        }
    }

    private static func list(from calendar: EKCalendar) -> TodoList {
        var list = TodoList(id: calendar.calendarIdentifier, title: calendar.title)
        if let color = NSColor(cgColor: calendar.cgColor)?.usingColorSpace(.sRGB) {
            list.red = Double(color.redComponent)
            list.green = Double(color.greenComponent)
            list.blue = Double(color.blueComponent)
        }
        return list
    }

    // Nonisolated so EventKit's completion closures aren't main-actor closures: they run on its own queue.

    nonisolated private static func fetch(_ store: EKEventStore, _ predicate: NSPredicate,
                                          completion: @escaping @Sendable ([TodoItem]) -> Void) {
        store.fetchReminders(matching: predicate) { reminders in
            let items = (reminders ?? []).map { r in
                TodoLogic.item(id: r.calendarItemIdentifier, title: r.title, dueComponents: r.dueDateComponents,
                               completed: r.isCompleted, completionDate: r.completionDate, created: r.creationDate)
            }
            completion(items)
        }
    }

    nonisolated private static func requestFullAccess(_ store: EKEventStore, completion: @escaping @Sendable (Bool) -> Void) {
        store.requestFullAccessToReminders { granted, _ in completion(granted) }
    }
}
