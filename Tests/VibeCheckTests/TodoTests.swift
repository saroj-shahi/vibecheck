import EventKit
import Foundation
import Testing
@testable import VibeCheck

/// To-do module logic with fixtures only: the real Reminders store is never opened.
struct TodoTests {
    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }
    private let cal = TodoTests.calendar
    /// 2026-11-23 14:00 London.
    private var now: Date { date(2026, 11, 23, 14) }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func item(_ id: String, due: Date? = nil, time: Bool = false, created: Date? = nil,
                      done: Date? = nil) -> TodoItem {
        TodoItem(id: id, title: id, due: due, dueHasTime: time, completed: done != nil, completionDate: done, created: created)
    }

    // MARK: Buckets and sorting

    @Test func bucketsFollowDayAndTime() {
        #expect(TodoLogic.bucket(item("a"), now: now, calendar: cal) == .none)
        #expect(TodoLogic.bucket(item("a", due: date(2026, 11, 22)), now: now, calendar: cal) == .overdue)
        // Date-only today isn't overdue even after midnight passed.
        #expect(TodoLogic.bucket(item("a", due: date(2026, 11, 23)), now: now, calendar: cal) == .today)
        // Timed today: overdue once the time has passed, due today before it.
        #expect(TodoLogic.bucket(item("a", due: date(2026, 11, 23, 9), time: true), now: now, calendar: cal) == .overdue)
        #expect(TodoLogic.bucket(item("a", due: date(2026, 11, 23, 18), time: true), now: now, calendar: cal) == .today)
        #expect(TodoLogic.bucket(item("a", due: date(2026, 11, 24)), now: now, calendar: cal) == .later)
    }

    @Test func openSortsOverdueThenTodayThenUndatedThenLater() {
        let items = [
            item("later2", due: date(2026, 12, 5)),
            item("undatedOld", created: date(2026, 11, 1)),
            item("today", due: date(2026, 11, 23, 18), time: true),
            item("later1", due: date(2026, 11, 25)),
            item("overdue2", due: date(2026, 11, 22)),
            item("undatedNew", created: date(2026, 11, 20)),
            item("overdue1", due: date(2026, 11, 20)),
            item("done", done: date(2026, 11, 23, 10)),
        ]
        let sorted = TodoLogic.sortOpen(items, now: now, calendar: cal).map(\.id)
        #expect(sorted == ["overdue1", "overdue2", "today", "undatedNew", "undatedOld", "later1", "later2"])
    }

    @Test func dueNowCountsOverdueAndToday() {
        let items = [item("a", due: date(2026, 11, 20)), item("b", due: date(2026, 11, 23)),
                     item("c", due: date(2026, 11, 30)), item("d"), item("e", due: date(2026, 11, 1), done: now)]
        #expect(TodoLogic.dueNowCount(items, now: now, calendar: cal) == 2)
    }

    // MARK: Completed

    @Test func completedNewestFirstAndLimited() {
        var items = (0..<14).map { item("d\($0)", done: date(2026, 11, 10 + $0)) }
        items.append(item("open"))
        items.append(item("noDate", done: nil))
        let recent = TodoLogic.recentCompleted(items)
        #expect(recent.count == TodoLogic.completedLimit)
        #expect(recent.first?.id == "d13")
        #expect(recent.last?.id == "d4")
        #expect(!recent.contains { !$0.completed })
        #expect(TodoLogic.recentCompleted(items, limit: 0).isEmpty)
    }

    // MARK: Menu bar label

    @Test func countLabelNeverPassesThreeCharacters() {
        #expect(TodoLogic.countLabel(0) == "0")
        #expect(TodoLogic.countLabel(7) == "7")
        #expect(TodoLogic.countLabel(99) == "99")
        #expect(TodoLogic.countLabel(100) == "99+")
        #expect(TodoLogic.countLabel(12_345) == "99+")
        #expect(TodoLogic.countLabel(-3) == "0")
    }

    // MARK: Mapping

    @Test func mapsDateOnlyAndTimedDueDates() {
        let dateOnly = TodoLogic.item(id: "x", title: "  Buy milk \n", dueComponents: DateComponents(year: 2026, month: 11, day: 24),
                                      completed: false, completionDate: now, created: nil, calendar: cal)
        #expect(dateOnly.title == "Buy milk")
        #expect(dateOnly.due == date(2026, 11, 24))
        #expect(!dateOnly.dueHasTime)
        #expect(dateOnly.completionDate == nil)   // only kept for completed items

        let timed = TodoLogic.item(id: "y", title: "Call", dueComponents: DateComponents(year: 2026, month: 11, day: 23, hour: 9, minute: 30),
                                   completed: true, completionDate: now, created: nil, calendar: cal)
        #expect(timed.due == date(2026, 11, 23, 9, 30))
        #expect(timed.dueHasTime)
        #expect(timed.completed && timed.completionDate == now)

        let none = TodoLogic.item(id: "z", title: nil, dueComponents: nil, completed: false, completionDate: nil, created: nil, calendar: cal)
        #expect(none.due == nil && !none.title.isEmpty)
        // Components without a full date aren't a due date.
        #expect(TodoLogic.due(from: DateComponents(hour: 9), calendar: cal) == nil)
    }

    @Test func authorizationStatusMapping() {
        #expect(TodoAccess.from(.notDetermined) == .notAsked)
        #expect(TodoAccess.from(.fullAccess) == .granted)
        #expect(TodoAccess.from(.writeOnly) == .writeOnly)
        #expect(TodoAccess.from(.denied) == .denied)
        #expect(TodoAccess.from(.restricted) == .restricted)
    }

    @Test func listFallsBackToDefaultThenFirst() {
        let lists = [TodoList(id: "a", title: "A"), TodoList(id: "b", title: "B")]
        #expect(TodoLogic.resolveList(id: "b", lists: lists, defaultID: "a")?.id == "b")
        #expect(TodoLogic.resolveList(id: "", lists: lists, defaultID: "b")?.id == "b")
        #expect(TodoLogic.resolveList(id: "gone", lists: lists, defaultID: nil)?.id == "a")
        #expect(TodoLogic.resolveList(id: "", lists: [], defaultID: "a") == nil)
    }

    @Test func dueTextNamesNearbyDays() {
        #expect(TodoLogic.dueText(item("a"), now: now, calendar: cal) == nil)
        #expect(TodoLogic.dueText(item("a", due: date(2026, 11, 23)), now: now, calendar: cal) == "Today")
        #expect(TodoLogic.dueText(item("a", due: date(2026, 11, 22)), now: now, calendar: cal) == "Yesterday")
        #expect(TodoLogic.dueText(item("a", due: date(2026, 11, 24)), now: now, calendar: cal) == "Tomorrow")
    }

    // MARK: Wiring

    @Test func moduleIsAnOffByDefaultExtra() {
        #expect(!Module.todo.enabledByDefault)
        #expect(!Module.todo.enabledForNewInstall)
        #expect(Module.todo.isExtra)
        #expect(Module.todo.symbol == "checkmark.circle")
        #expect(Module.todo.labelStyles == [.standard, .valueOnly])
        #expect(DeckModuleOption.todo.module == .todo)
        #expect(SettingsBackup.keys.contains("todoListID"))
        #expect(RemindersStore.isTestProcess)
    }
}
