import AppKit
import SwiftUI

struct ClockPanel: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SystemStats.self) private var stats
    @Environment(\.deckShowsBack) private var showsBack
    private var ticker: ClockTicker { .shared }
    private var calendarStore: CalendarStore { .shared }
    private var remindersStore: RemindersStore { .shared }
    /// Time travel offset in minutes (−720…+720). 0 means live "Now".
    @State private var travelMinutes = 0
    @State private var selectedDate: Date?
    @State private var hoveredEventID: String?
    @State private var expandedEventID: String?
    @State private var compactClocks = false
    /// Measured section heights so DeckRoot still knows the natural total height when auto-sizing.
    @State private var topHeight: CGFloat = 0
    @State private var agendaHeaderHeight: CGFloat = 0
    @State private var agendaBodyHeight: CGFloat = 0
    @State private var bottomHeight: CGFloat = 0

    var body: some View {
        let now = ticker.now
        let displayDate = TimeTravel.targetDate(from: now, offsetMinutes: travelMinutes)
        let calEnabled = settings.clock.showCalendarEvents
        let visibleEvents: [CalendarEvent] = calEnabled && calendarStore.access == .granted
            ? CalendarLogic.filter(calendarStore.events,
                                   hiddenCalendarIDs: settings.clock.hiddenCalendarIDs,
                                   showAllDay: settings.clock.showAllDayEvents,
                                   hidePastToday: settings.clock.hidePastEventsToday,
                                   now: now)
            : []
        let dots = calEnabled && calendarStore.access == .granted
            ? CalendarLogic.dotColors(for: visibleEvents).mapValues { list in
                list.map { Color(red: $0.0, green: $0.1, blue: $0.2) }
            }
            : [:]
        let hoveredDays: Set<Date> = {
            guard let hoveredEventID, let ev = visibleEvents.first(where: { $0.id == hoveredEventID }) else { return [] }
            return Set(ev.spannedDays())
        }()

        // Natural total height for auto-sizing the panel when no custom height is set.
        let naturalTotal = topHeight
            + (calEnabled ? agendaHeaderHeight + agendaBodyHeight + 20 : 0)
            + bottomHeight
            + (showsBack ? 12 : 28)

        VStack(alignment: .leading, spacing: 0) {
            // Pinned top: optional standalone header + sticky Month Calendar.
            VStack(alignment: .leading, spacing: 12) {
                if !showsBack { PanelHeader(module: .clock) }
                MonthCalendar(today: now,
                              showWeekNumbers: settings.clock.showWeekNumbersInCalendar,
                              selectedDate: $selectedDate,
                              eventDots: dots,
                              highlightedDays: hoveredDays,
                              onMonthChange: { month in
                                  if settings.clock.showCalendarEvents {
                                      calendarStore.ensureMonthLoaded(month)
                                  }
                              })
            }
            .padding(.horizontal, 16)
            .padding(.top, showsBack ? 0 : 16)
            .padding(.bottom, 10)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }

            // Middle: ONLY the events section scrolls while the calendar stays pinned above.
            if calEnabled {
                Divider().padding(.horizontal, 16)

                calendarAgendaHeader(now: now, events: visibleEvents)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { agendaHeaderHeight = $0 }

                ScrollView(.vertical) {
                    calendarAgendaBody(now: now, events: visibleEvents)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { agendaBodyHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.automatic)
                .frame(minHeight: 72, maxHeight: .infinity)
            }

            // Pinned bottom: World clocks + Time Travel + standard footer.
            VStack(alignment: .leading, spacing: 12) {
                if !settings.clock.worldClocks.isEmpty {
                    Divider()
                    worldClocksSection(now: now, displayDate: displayDate)
                }
                Divider()
                HStack {
                    Text("Up \(Fmt.uptime(stats.uptime))")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/sarojshahi")!)
                    } label: { Label("Support", systemImage: "heart") }
                        .help("Support VibeCheck: Buy Me a Coffee")
                    Button {
                        (NSApp.delegate as? AppDelegate)?.showSettings()
                    } label: { Image(systemName: "gearshape") }
                        .help("Settings")
                    Button {
                        NSApp.terminate(nil)
                    } label: { Image(systemName: "power") }
                        .help("Quit VibeCheck")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomHeight = $0 }
        }
        .frame(width: Deck.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .preference(key: DeckHeightKey.self, value: naturalTotal)
        .onAppear {
            settings.clock.isPanelOpen = true
            if settings.clock.showCalendarEvents {
                calendarStore.activate(requestAccess: false)
            }
            if settings.clock.showRemindersInAgenda {
                remindersStore.ensureStarted()
            }
        }
        .onDisappear {
            settings.clock.isPanelOpen = false
            travelMinutes = 0
            hoveredEventID = nil
        }
    }

    // MARK: - Calendar Agenda

    private func calendarAgendaHeader(now: Date, events: [CalendarEvent]) -> some View {
        HStack(spacing: 6) {
            SectionTitle(text: selectedDate == nil ? "Upcoming" : "Events")
            Spacer()
            if calendarStore.access == .granted,
               let joinable = CalendarLogic.nextJoinableCall(in: events, now: now, lookaheadMinutes: 15),
               let link = joinable.videoCall {
                Button {
                    NSWorkspace.shared.open(link.url)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: link.service.symbol).font(.system(size: 9.5, weight: .semibold))
                        Text("Join \(link.service.title)").font(.caption2.weight(.semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .help("Join \(joinable.title)")
            }
        }
    }

    @ViewBuilder
    private func calendarAgendaBody(now: Date, events: [CalendarEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {

            switch calendarStore.access {
            case .notAsked:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Connect Apple Calendar to see upcoming events and one-click video call links here.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Connect Calendar") { calendarStore.activate(requestAccess: true) }
                        .controlSize(.small)
                }
            case .denied, .writeOnly, .restricted:
                VStack(alignment: .leading, spacing: 6) {
                    Text(calendarStore.access == .restricted
                         ? "Calendar access is restricted on this Mac."
                         : "VibeCheck isn't allowed to read Calendars. Turn it on in System Settings › Privacy & Security › Calendars.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if calendarStore.access != .restricted {
                        Button("Open Privacy Settings") { CalendarStore.openPrivacySettings() }
                            .controlSize(.small)
                    }
                }
            case .granted:
                let startDay = selectedDate ?? now
                let spanDays = selectedDate == nil ? settings.clock.calendarDaysAhead : 1
                let groups = CalendarLogic.groupByDay(events, from: startDay, days: spanDays)
                let agendaReminders = remindersForAgenda(from: startDay, days: spanDays)
                if !calendarStore.loaded {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                } else if groups.isEmpty && agendaReminders.isEmpty {
                    Text(selectedDate == nil
                         ? String(localized: "No events in the next \(settings.clock.calendarDaysAhead) days.")
                         : String(localized: "No events on this day."))
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(CalendarLogic.dayHeader(group.day, today: now))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(group.events.prefix(12)) { event in
                                    CalendarEventRow(
                                        event: event,
                                        now: now,
                                        expanded: expandedEventID == event.id,
                                        worldClocks: settings.clock.worldClocks,
                                        onToggleExpand: {
                                            withAnimation(.easeOut(duration: 0.15)) {
                                                expandedEventID = expandedEventID == event.id ? nil : event.id
                                            }
                                        },
                                        onHoverChange: { hovering in
                                            hoveredEventID = hovering ? event.id : (hoveredEventID == event.id ? nil : hoveredEventID)
                                        }
                                    )
                                }
                                if group.events.count > 12 {
                                    Text("+\(group.events.count - 12) more")
                                        .font(.caption2).foregroundStyle(.tertiary).padding(.leading, 10)
                                }
                            }
                        }
                        if !agendaReminders.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Reminders").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(agendaReminders.prefix(6)) { item in
                                    AgendaReminderRow(item: item) {
                                        remindersStore.setCompleted(item, true)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func remindersForAgenda(from startDay: Date, days: Int) -> [TodoItem] {
        guard settings.clock.showRemindersInAgenda, remindersStore.access == .granted else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: startDay)
        guard let end = cal.date(byAdding: .day, value: days, to: start) else { return [] }
        return remindersStore.open.filter { item in
            guard let due = item.due else { return false }
            return due >= start && due < end
        }
    }

    // MARK: - World Clocks

    @ViewBuilder
    private func worldClocksSection(now: Date, displayDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SectionTitle(text: "World clocks")
                Spacer()
                if travelMinutes != 0 {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { travelMinutes = 0 }
                    } label: {
                        HStack(spacing: 3) {
                            Text(TimeTravel.offsetLabel(minutes: travelMinutes))
                                .font(.caption2.weight(.semibold).monospacedDigit())
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Reset time travel to now")
                }
                if settings.clock.worldClocks.count > 3 {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { compactClocks.toggle() }
                    } label: {
                        Image(systemName: compactClocks ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(compactClocks ? "Expand world clocks" : "Compact world clocks")
                }
            }

            if compactClocks {
                compactWorldClockGrid(at: displayDate)
            } else {
                VStack(spacing: 4) {
                    ForEach(settings.clock.worldClocks) { clock in
                        WorldClockRow(clock: clock, now: displayDate) {
                            togglePin(clock)
                        }
                    }
                }
            }

            TimeTravelBar(minutes: $travelMinutes, now: now)
        }
    }

    private func compactWorldClockGrid(at date: Date) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(settings.clock.worldClocks) { clock in
                HStack(spacing: 4) {
                    Image(systemName: clock.isDaytime(at: date) ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(clock.isDaytime(at: date) ? .yellow : .indigo)
                    Text(clock.name).font(.caption).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(clock.formattedTime(at: date))
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.quaternary.opacity(0.5)))
                .contentShape(Rectangle())
                .onTapGesture { copyToPasteboard(clock.formattedTime(at: date)) }
                .help("Click to copy \(clock.name) time")
            }
        }
    }

    private func togglePin(_ clock: WorldClock) {
        guard let idx = settings.clock.worldClocks.firstIndex(where: { $0.id == clock.id }) else { return }
        settings.clock.worldClocks[idx].showInMenuBar.toggle()
    }
}

// MARK: - Event Row & Details

private struct CalendarEventRow: View {
    let event: CalendarEvent
    let now: Date
    let expanded: Bool
    let worldClocks: [WorldClock]
    let onToggleExpand: () -> Void
    let onHoverChange: (Bool) -> Void
    @State private var hovering = false

    private var color: Color { Color(red: event.red, green: event.green, blue: event.blue) }

    var body: some View {
        let active = event.isHappening(at: now)
        let past = event.isPast(at: now)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.callout.weight(active ? .semibold : .regular))
                        .lineLimit(expanded ? 3 : 1)
                    HStack(spacing: 5) {
                        Text(timeLabel)
                            .font(.caption.weight(active ? .medium : .regular).monospacedDigit())
                            .foregroundStyle(active ? .primary : .secondary)
                        if active || event.startsSoon(at: now, withinMinutes: 60) {
                            Text("· \(CalendarLogic.countdownText(for: event, now: now))")
                                .font(.caption.weight(active ? .medium : .regular).monospacedDigit())
                                .foregroundStyle(active ? .primary : .secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let link = event.videoCall {
                    Button {
                        NSWorkspace.shared.open(link.url)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: link.service.symbol).font(.system(size: 9.5, weight: .semibold))
                            Text("Join").font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(active || event.startsSoon(at: now, withinMinutes: 15)
                                                   ? Color.accentColor : Color.secondary.opacity(0.18)))
                        .foregroundStyle(active || event.startsSoon(at: now, withinMinutes: 15) ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .help("Join \(link.service.title)")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggleExpand)

            if expanded {
                VStack(alignment: .leading, spacing: 5) {
                    if !event.calendarTitle.isEmpty {
                        Label(event.calendarTitle, systemImage: "calendar")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let loc = event.location, !loc.isEmpty {
                        Label(loc, systemImage: "mappin.and.ellipse")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if !event.attendeeNames.isEmpty {
                        let shown = event.attendeeNames.prefix(4).joined(separator: ", ")
                        let suffix = event.attendeeNames.count > 4 ? " +\(event.attendeeNames.count - 4)" : ""
                        Label("\(shown)\(suffix)", systemImage: "person.2")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if !event.isAllDay && !worldClocks.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(worldClocks.prefix(3)) { clock in
                                Text("\(clock.menuBarTag) \(clock.formattedTime(at: event.startDate))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                    HStack(spacing: 8) {
                        Button("Open in Calendar") {
                            CalendarDateHelper.openCalendarApp(at: event.startDate)
                        }
                        .controlSize(.mini)
                        if let link = event.videoCall {
                            Button("Copy Link") {
                                copyToPasteboard(link.url.absoluteString)
                            }
                            .controlSize(.mini)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(.leading, 11)
                .padding(.bottom, 2)
            }
        }
        .opacity(past ? 0.55 : 1)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(active ? AnyShapeStyle(Color.accentColor.opacity(0.10))
                  : (hovering || expanded) ? AnyShapeStyle(.quaternary.opacity(0.55)) : AnyShapeStyle(.clear)))
        .onHover { isHovering in
            hovering = isHovering
            onHoverChange(isHovering)
        }
        .contextMenu {
            if let link = event.videoCall {
                Button("Join \(link.service.title)") { NSWorkspace.shared.open(link.url) }
                Button("Copy Meeting Link") { copyToPasteboard(link.url.absoluteString) }
                Divider()
            }
            Button("Open in Calendar") { CalendarDateHelper.openCalendarApp(at: event.startDate) }
            Button("Copy Title") { copyToPasteboard(event.title) }
        }
    }

    private var timeLabel: String {
        if event.isAllDay { return String(localized: "All day") }
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}

private struct AgendaReminderRow: View {
    let item: TodoItem
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("Mark as done")
            Text(item.title).font(.callout).lineLimit(1)
            Spacer()
            if let due = TodoLogic.dueText(item, now: Date()) {
                Text(due).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }
}

// MARK: - World Clock Row & Time Travel

struct WorldClockRow: View {
    let clock: WorldClock
    let now: Date
    var onTogglePin: (() -> Void)? = nil
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: clock.isDaytime(at: now) ? "sun.max.fill" : "moon.fill")
                .foregroundStyle(clock.isDaytime(at: now) ? .yellow : .indigo)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(clock.name).font(.callout).lineLimit(1)
                    if clock.showInMenuBar {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .help("Shown in menu bar")
                    }
                }
                Text(copied ? String(localized: "Copied") : clock.relativeDescription(at: now))
                    .font(.caption)
                    .foregroundStyle(copied ? Color.accentColor : .secondary)
            }
            Spacer()
            Text(clock.formattedTime(at: now))
                .font(.title3.monospacedDigit())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? AnyShapeStyle(.quaternary.opacity(0.55)) : AnyShapeStyle(.clear)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { copyTime() }
        .help("Click to copy time")
        .contextMenu {
            Button("Copy Time") { copyTime() }
            Button("Copy ISO 8601") { copyToPasteboard(clock.iso8601String(at: now)); flashCopied() }
            if let onTogglePin {
                Divider()
                Button(clock.showInMenuBar ? "Remove from Menu Bar" : "Show in Menu Bar", action: onTogglePin)
            }
        }
    }

    private func copyTime() {
        copyToPasteboard("\(clock.name): \(clock.formattedTime(at: now))")
        flashCopied()
    }

    private func flashCopied() {
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}

private func copyToPasteboard(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
}

/// Scrubbable ±12h Time Travel bar. Snaps to whole hours normally, or 15-minute steps while holding ⌥,
/// with subtle haptic detents at each hour mark.
struct TimeTravelBar: View {
    @Binding var minutes: Int
    let now: Date
    @State private var lastHourDetent: Int = 0

    var body: some View {
        let shifted = TimeTravel.targetDate(from: now, offsetMinutes: minutes)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.system(size: 11))
                    .foregroundStyle(minutes == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
                Slider(
                    value: Binding(
                        get: { Double(minutes) },
                        set: { raw in
                            let fine = NSEvent.modifierFlags.contains(.option)
                            let snapped = TimeTravel.snap(raw, fine: fine)
                            if snapped != minutes {
                                let hour = snapped / 60
                                if snapped % 60 == 0 && hour != lastHourDetent {
                                    lastHourDetent = hour
                                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                                }
                                minutes = snapped
                            }
                        }
                    ),
                    in: Double(TimeTravel.rangeMinutes.lowerBound)...Double(TimeTravel.rangeMinutes.upperBound)
                )
                .controlSize(.small)
                .help("Drag to preview world clocks (±12h). Hold ⌥ for 15-minute steps.")
                .accessibilityLabel("Time travel")
                .accessibilityValue(TimeTravel.offsetLabel(minutes: minutes))

                Text(minutes == 0 ? String(localized: "Now") : shifted.formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(minutes == 0 ? .secondary : .primary)
                    .frame(width: 54, alignment: .trailing)
            }
        }
        .padding(.top, 2)
    }
}

/// Month grid with today highlighted, optional week numbers, event dots, and day selection.
/// Click the month title to jump back to today; ⌥-click arrows to step by year.
struct MonthCalendar: View {
    let today: Date
    var showWeekNumbers: Bool = false
    @Binding var selectedDate: Date?
    /// Start-of-day dates that have calendar events (value = dot colors, max 3 drawn).
    var eventDots: [Date: [Color]] = [:]
    /// Start-of-day dates to softly highlight (e.g. hovered multi-day event).
    var highlightedDays: Set<Date> = []
    var onMonthChange: ((Date) -> Void)? = nil

    @State private var monthOffset = 0
    private let calendar = Calendar.current

    var body: some View {
        let shown = calendar.date(byAdding: .month, value: monthOffset, to: today) ?? today
        let month = calendar.dateInterval(of: .month, for: shown)!
        let leading = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: shown)?.count ?? 30
        let totalCells = leading + dayCount
        let rowCount = (totalCells + 6) / 7
        let todayStart = calendar.startOfDay(for: today)
        let selectedStart = selectedDate.map { calendar.startOfDay(for: $0) }

        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    monthOffset = 0
                    selectedDate = nil
                } label: {
                    Text(shown.formatted(.dateTime.month(.wide).year()))
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)
                .help(monthOffset == 0 && selectedDate == nil ? "Current month" : "Jump back to today")

                Spacer()

                if monthOffset != 0 || selectedDate != nil {
                    Button("Today") {
                        monthOffset = 0
                        selectedDate = nil
                    }
                    .font(.caption)
                }
                Button {
                    let step = NSEvent.modifierFlags.contains(.option) ? 12 : 1
                    monthOffset -= step
                } label: { Image(systemName: "chevron.left") }
                    .help("Previous month (⌥-click for previous year)")
                Button {
                    let step = NSEvent.modifierFlags.contains(.option) ? 12 : 1
                    monthOffset += step
                } label: { Image(systemName: "chevron.right") }
                    .help("Next month (⌥-click for next year)")
                Button {
                    CalendarDateHelper.openCalendarApp(at: selectedDate ?? today)
                } label: { Image(systemName: "arrow.up.forward.app") }
                    .help("Open in Calendar")
            }
            .buttonStyle(.borderless)

            let columns = (showWeekNumbers ? [GridItem(.fixed(22), spacing: 2)] : [])
                + Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

            LazyVGrid(columns: columns, spacing: 3) {
                if showWeekNumbers {
                    Text("W").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                }
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(0..<rowCount, id: \.self) { row in
                    if showWeekNumbers {
                        let firstDayInRow = max(1, row * 7 - leading + 1)
                        let rowDate = calendar.date(byAdding: .day, value: firstDayInRow - 1, to: month.start) ?? month.start
                        Text("\(CalendarDateHelper.weekNumber(for: rowDate, calendar: calendar))")
                            .font(.system(size: 9.5).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(height: 24)
                    }
                    ForEach(0..<7, id: \.self) { col in
                        let index = row * 7 + col
                        let day = index - leading + 1
                        if day >= 1 && day <= dayCount,
                           let date = calendar.date(byAdding: .day, value: day - 1, to: month.start) {
                            let dayStart = calendar.startOfDay(for: date)
                            let isToday = dayStart == todayStart
                            let isSelected = selectedStart == dayStart
                            let isHighlighted = highlightedDays.contains(dayStart)
                            let isWeekend = calendar.isDateInWeekend(date)
                            let dots = eventDots[dayStart] ?? []

                            Button {
                                selectedDate = (selectedStart == dayStart) ? nil : dayStart
                            } label: {
                                VStack(spacing: 1) {
                                    Text("\(day)")
                                        .font(.caption.monospacedDigit())
                                        .fontWeight(isToday || isSelected ? .semibold : .regular)
                                        .foregroundStyle(isToday ? Color.white
                                                         : isSelected ? Color.accentColor
                                                         : isWeekend ? Color.secondary : Color.primary)
                                    HStack(spacing: 2) {
                                        ForEach(Array(dots.prefix(3).enumerated()), id: \.offset) { _, color in
                                            Circle()
                                                .fill(isToday ? Color.white.opacity(0.9) : color)
                                                .frame(width: 3.5, height: 3.5)
                                        }
                                    }
                                    .frame(height: 4)
                                }
                                .frame(width: 26, height: 24)
                                .background {
                                    if isToday {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor)
                                    } else if isSelected {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.accentColor.opacity(0.16))
                                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1))
                                    } else if isHighlighted {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.accentColor.opacity(0.12))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        } else {
                            Color.clear.frame(height: 24)
                        }
                    }
                }
            }

            if let selectedStart {
                HStack(spacing: 6) {
                    Text(selectedStart.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.caption.weight(.medium))
                    Text("·").foregroundStyle(.tertiary)
                    Text(CalendarDateHelper.relativeDayLabel(for: selectedStart, today: today, calendar: calendar))
                        .font(.caption).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text("W\(CalendarDateHelper.weekNumber(for: selectedStart, calendar: calendar))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        selectedDate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear selected day")
                }
                .padding(.top, 2)
            }
        }
        .onChange(of: monthOffset) { _, _ in
            if let next = calendar.date(byAdding: .month, value: monthOffset, to: today) {
                onMonthChange?(next)
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}
