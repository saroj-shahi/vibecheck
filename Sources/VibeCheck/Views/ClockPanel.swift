import SwiftUI

struct ClockPanel: View {
    @Environment(AppSettings.self) private var settings
    private var ticker: ClockTicker { .shared }

    var body: some View {
        let now = ticker.now
        Panel(module: .clock, headline: now.formatted(date: .omitted, time: .shortened)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(now.formatted(.dateTime.hour().minute().second()))
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                    .font(.callout).foregroundStyle(.secondary)
            }

            MonthCalendar(today: now)

            if !settings.worldClocks.isEmpty {
                VStack(spacing: 8) {
                    SectionTitle(text: "World clocks").frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(settings.worldClocks) { clock in
                        WorldClockRow(clock: clock, now: now)
                    }
                }
            }
        }
        .onAppear { settings.isClockPanelOpen = true }
        .onDisappear { settings.isClockPanelOpen = false }
    }
}

struct WorldClockRow: View {
    let clock: WorldClock
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: clock.isDaytime(at: now) ? "sun.max.fill" : "moon.fill")
                .foregroundStyle(clock.isDaytime(at: now) ? .yellow : .indigo)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(clock.name).font(.callout)
                Text(clock.relativeDescription(at: now)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: clock.timeZone)))
                .font(.title3.monospacedDigit())
        }
    }
}

/// Month grid with today highlighted; arrows browse months, the title opens Calendar.
struct MonthCalendar: View {
    let today: Date
    @State private var monthOffset = 0
    private let calendar = Calendar.current

    var body: some View {
        let shown = calendar.date(byAdding: .month, value: monthOffset, to: today) ?? today
        let month = calendar.dateInterval(of: .month, for: shown)!
        let leading = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: shown)?.count ?? 30
        let isCurrentMonth = calendar.isDate(shown, equalTo: today, toGranularity: .month)
        let todayNumber = calendar.component(.day, from: today)

        VStack(spacing: 6) {
            HStack {
                Button { ClockTicker.openCalendarApp() } label: {
                    Text(shown.formatted(.dateTime.month(.wide).year())).font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)
                .help("Open Calendar")
                Spacer()
                if monthOffset != 0 {
                    Button("Today") { monthOffset = 0 }.font(.caption)
                }
                Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }
                Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.borderless)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 20) }
                ForEach(1...dayCount, id: \.self) { day in
                    let isToday = isCurrentMonth && day == todayNumber
                    Text("\(day)")
                        .font(.caption.monospacedDigit())
                        .frame(width: 22, height: 20)
                        .foregroundStyle(isToday ? Color.white : Color.primary)
                        .background { if isToday { Circle().fill(Color.accentColor) } }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}
