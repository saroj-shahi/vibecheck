import SwiftUI

/// One local calendar day of mid / cooked time.
struct VibeDay: Equatable, Sendable {
    var start: Date
    var midMinutes: Double = 0
    var cookedMinutes: Double = 0
    var culprit: String?
    /// Stretches of the day as fractions 0...1 of its length.
    var pieces: [Piece] = []

    struct Piece: Equatable, Sendable {
        var start: Double
        var end: Double
        var vibe: Vibe
    }

    var totalMinutes: Double { midMinutes + cookedMinutes }
}

extension VibeReplayStore {
    /// The last `days` local days (oldest first, today last). Episodes crossing midnight are split.
    nonisolated static func dayBuckets(_ episodes: [VibeEpisode], days: Int, now: Date = Date(),
                                       calendar: Calendar = .current) -> [VibeDay] {
        let today = calendar.startOfDay(for: now)
        var out: [VibeDay] = []
        for back in stride(from: days - 1, through: 0, by: -1) {
            // startOfDay again: on a DST day without a midnight, stepping can land at 1 am.
            guard let shifted = calendar.date(byAdding: .day, value: -back, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: shifted))
            else { continue }
            let start = calendar.startOfDay(for: shifted)
            let t0 = start.timeIntervalSince1970, t1 = next.timeIntervalSince1970
            var day = VibeDay(start: start)
            var byCulprit: [String: Double] = [:]
            for e in episodes.sorted(by: { $0.start < $1.start }) where e.end > t0 && e.start < t1 {
                let s = max(e.start, t0)
                let f = min(max(e.end, e.start + 60), t1)   // same visible sliver as the 24 h strip
                guard f > s else { continue }
                let minutes = (f - s) / 60
                if e.level == .cooked { day.cookedMinutes += minutes } else { day.midMinutes += minutes }
                if let c = e.culprit { byCulprit[c, default: 0] += minutes }
                day.pieces.append(.init(start: (s - t0) / (t1 - t0), end: (f - t0) / (t1 - t0), vibe: e.level))
            }
            day.culprit = byCulprit.max { ($0.value, $1.key) < ($1.value, $0.key) }
                .map { Module(rawValue: $0.key)?.title ?? $0.key }
            out.append(day)
        }
        return out
    }

    /// "Tue 18 Nov: 42 min mid, 9 min cooked, mostly CPU"
    nonisolated static func dayDescription(_ day: VibeDay, calendar: Calendar = .current) -> String {
        var f = Date.FormatStyle(timeZone: calendar.timeZone)
        f.calendar = calendar
        let label = day.start.formatted(f.weekday(.abbreviated).day().month(.abbreviated))
        let mid = Int(day.midMinutes.rounded()), cooked = Int(day.cookedMinutes.rounded())
        if mid == 0 && cooked == 0 { return String(localized: "\(label): vibing all day") }
        var text = String(localized: "\(label): \(mid) min mid, \(cooked) min cooked")
        if let c = day.culprit { text += String(localized: ", mostly \(c)") }
        return text
    }

    /// Short row label: "Today" or "Mon".
    nonisolated static func dayLabel(_ day: VibeDay, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day.start, inSameDayAs: now) { return String(localized: "Today") }
        var f = Date.FormatStyle(timeZone: calendar.timeZone)
        f.calendar = calendar
        return day.start.formatted(f.weekday(.abbreviated))
    }
}

enum VibeTimelineRange: String, CaseIterable, Identifiable {
    case day = "24H", week = "7D", month = "30D"
    var id: String { rawValue }
}

/// A thin bar of vibing / mid / cooked over the last 24 hours (or 7 / 30 days), with the weekly sentence under it.
/// Reads `SystemStats.vibeReplay`; ready to drop into the deck home.
struct VibeStripView: View {
    @Environment(SystemStats.self) private var stats
    @AppStorage("vibeTimelineRange") private var rangeRaw = VibeTimelineRange.day.rawValue
    @State private var hoveredDay: Date?
    @State private var hoveredSummary: String?

    private var range: VibeTimelineRange { VibeTimelineRange(rawValue: rangeRaw) ?? .day }

    var body: some View {
        let episodes = stats.vibeReplay.all
        VStack(alignment: .leading, spacing: 4) {
            switch range {
            case .day: dayStrip(episodes)
            case .week: weekRows(episodes)
            case .month: monthBars(episodes)
            }
            HStack {
                Text(hoveredSummary ?? VibeReplayStore.weeklySummary(episodes))
                    .foregroundStyle(hoveredSummary != nil ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Picker("Range", selection: $rangeRaw) {
                    ForEach(VibeTimelineRange.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .animation(.easeOut(duration: 0.12), value: hoveredSummary)
        }
        .onChange(of: rangeRaw) { _, _ in
            hoveredDay = nil
            hoveredSummary = nil
        }
    }

    private func dayStrip(_ episodes: [VibeEpisode]) -> some View {
        GeometryReader { geo in
            let segments = VibeReplayStore.segments(episodes)
            ZStack(alignment: .leading) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    Rectangle().fill(seg.vibe.color.opacity(seg.vibe == .vibing ? 0.55 : 1))
                        .frame(width: max(1, geo.size.width * (seg.end - seg.start)))
                        .offset(x: geo.size.width * seg.start)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vibe over the last 24 hours. \(VibeReplayStore.weeklySummary(episodes))")
    }

    private func weekRows(_ episodes: [VibeEpisode]) -> some View {
        let now = Date()
        let days = VibeReplayStore.dayBuckets(episodes, days: 7, now: now)
        let summary = days.map { "\(VibeReplayStore.dayLabel($0, now: now)): \(Int($0.totalMinutes.rounded())) min" }
            .joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(days, id: \.start) { day in
                let desc = VibeReplayStore.dayDescription(day)
                let isHovered = hoveredDay == day.start
                HStack(spacing: 6) {
                    Text(VibeReplayStore.dayLabel(day, now: now))
                        .font(.system(size: 9, weight: isHovered ? .semibold : .regular))
                        .foregroundStyle(isHovered ? .primary : .secondary)
                        .frame(width: 34, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Vibe.vibing.color.opacity(isHovered ? 0.55 : 0.35))
                            ForEach(Array(day.pieces.enumerated()), id: \.offset) { _, p in
                                Rectangle().fill(p.vibe.color)
                                    .frame(width: max(1, geo.size.width * (p.end - p.start)))
                                    .offset(x: geo.size.width * p.start)
                            }
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: isHovered ? 7 : 6)
                }
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside {
                        hoveredDay = day.start
                        hoveredSummary = desc
                        if day.cookedMinutes > 0 {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                    } else if hoveredDay == day.start {
                        hoveredDay = nil
                        hoveredSummary = nil
                    }
                }
                .help(desc)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vibe over the last 7 days, minutes mid or cooked per day. \(summary)")
    }

    private func monthBars(_ episodes: [VibeEpisode]) -> some View {
        let days = VibeReplayStore.dayBuckets(episodes, days: 30)
        let maxMinutes = max(60, days.map(\.totalMinutes).max() ?? 0)
        let height: CGFloat = 40
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(days, id: \.start) { day in
                let desc = VibeReplayStore.dayDescription(day)
                let isHovered = hoveredDay == day.start
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle().fill(Vibe.mid.color)
                        .frame(height: height * day.midMinutes / maxMinutes)
                    Rectangle().fill(Vibe.cooked.color)
                        .frame(height: height * day.cookedMinutes / maxMinutes)
                }
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                .background(Vibe.vibing.color.opacity(isHovered ? 0.36 : 0.15))
                .opacity(hoveredDay == nil || isHovered ? 1 : 0.55)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside {
                        hoveredDay = day.start
                        hoveredSummary = desc
                    } else if hoveredDay == day.start {
                        hoveredDay = nil
                        hoveredSummary = nil
                    }
                }
                .help(desc)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(desc)
            }
        }
        .frame(height: height)
    }
}
