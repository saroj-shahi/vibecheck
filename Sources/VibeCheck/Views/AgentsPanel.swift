import SwiftUI

/// Token usage of local AI coding agents (Claude Code, Codex), read from their logs on this Mac.
struct AgentsPanel: View {
    private var store: AgentUsageStore { .shared }

    var body: some View {
        let sample = store.sample
        Panel(module: .agents, headline: sample.scanned && !sample.agents.isEmpty ? Fmt.tokens(sample.today.total) : "—",
              subtitle: sample.agents.isEmpty ? nil : "tokens today") {
            if !sample.scanned {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else if sample.agents.isEmpty {
                Text("No agent usage found on this Mac. VibeCheck reads Claude Code (~/.claude), Codex (~/.codex), GitHub Copilot CLI (~/.copilot) and OpenCode (~/.local/share/opencode).")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(text: "Last 24 hours")
                    HourlyBars(values: sample.hourly, color: Palette.agents)
                        .frame(height: 56)
                }
                ForEach(sample.agents) { AgentCard(summary: $0) }
                if !sample.projectsToday.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionTitle(text: "Busiest projects today")
                        ForEach(sample.projectsToday.prefix(5), id: \.name) { project in
                            StatRow(label: project.name, value: Fmt.tokens(project.tokens))
                        }
                    }
                }
                DetailsDisclosure(.agents) {
                    VStack(spacing: 4) {
                        StatRow(label: "Input", value: Fmt.tokens(sample.today.input))
                        StatRow(label: "Output", value: Fmt.tokens(sample.today.output))
                        StatRow(label: "Cache writes", value: Fmt.tokens(sample.today.cacheWrite))
                        StatRow(label: "Cache reads", value: Fmt.tokens(sample.today.cacheRead))
                        StatRow(label: "Last 7 days", value: Fmt.tokens(sample.week.total))
                    }
                    ForEach(sample.agents.filter { !$0.modelsToday.isEmpty }) { summary in
                        VStack(alignment: .leading, spacing: 4) {
                            SectionTitle(text: "\(summary.agent.title) models today")
                            ForEach(summary.modelsToday.prefix(4), id: \.name) { model in
                                StatRow(label: model.name, value: Fmt.tokens(model.tokens))
                            }
                        }
                    }
                    Text("Read from local logs; nothing leaves your Mac. Totals include cache reads, as usage tools usually count them. The Claude 5-hour window is an estimate.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { store.refresh(fullWalk: true) }
    }
}

private struct AgentCard: View {
    let summary: AgentSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.agent.title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(Fmt.tokens(summary.today.total)).font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            if let block = summary.block {
                Text("This 5-hour window: \(Fmt.tokens(block.tokens.total)) · resets \(block.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !summary.limits.isEmpty {
                // Ticks on its own so the countdown and pace marker move between scans.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(summary.limits.sorted { $0.windowMinutes < $1.windowMinutes }, id: \.windowMinutes) {
                            LimitGauge(limit: $0, now: context.date)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            Text(lastActiveText).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.55)))
        .accessibilityElement(children: .combine)
    }

    private var lastActiveText: String {
        guard let last = summary.lastActive else { return "No activity this week" }
        return "Last active \(last.formatted(.relative(presentation: .named)))"
    }

}

/// One provider limit: how much is left, how fast it's going, and where "now" sits in the window.
struct LimitGauge: View {
    let limit: RateWindow
    let now: Date

    var body: some View {
        let ahead = limit.isAheadOfPace(now: now)
        let color = limit.gaugeColor(now: now)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.cardTitle).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let burn = limit.burnPerHour(now: now) {
                    Text(String(format: "%.1f%%/hr", burn))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ahead ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
                        .help("Average since this window started")
                }
            }
            Text("\(Int(limit.leftPercent.rounded()))% left")
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            PaceBar(used: limit.usedPercent / 100, elapsed: limit.elapsedFraction(now: now), color: color)
                .frame(height: 12)
            Text(resetText)
                .font(.caption).foregroundStyle(.secondary)
            if ahead {
                Text("Going faster than the clock: at this pace it runs out before it resets.")
                    .font(.caption2).foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(limit.cardTitle): \(Int(limit.leftPercent.rounded())) percent left, resets in \(limit.countdown(now: now))")
    }

    private var resetText: String {
        let when = Calendar.current.isDateInToday(limit.resetsAt)
            ? limit.resetsAt.formatted(date: .omitted, time: .shortened)
            : limit.resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return "Resets in \(limit.countdown(now: now)) (\(when))"
    }
}

/// Used share as a filled track, with a knob marking how much of the window has passed.
/// Fill past the knob means the limit is being used faster than time goes by.
struct PaceBar: View {
    let used: Double
    let elapsed: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 6)
                Capsule().fill(color).frame(width: max(6, width * min(max(used, 0), 1)), height: 6)
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .frame(width: 12, height: 12)
                    .offset(x: min(max(width * elapsed - 6, 0), width - 12))
                    .help("Time passed in this window")
            }
            .frame(maxHeight: .infinity)
        }
        .animation(Deck.animation, value: used)
    }
}

/// 24 hourly bars, newest on the right.
struct HourlyBars: View {
    let values: [Double]
    let color: Color

    var body: some View {
        let peak = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(value > 0 ? color : Color.secondary.opacity(0.2))
                    .frame(height: max(2, CGFloat(value / peak) * 56))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .accessibilityHidden(true)
    }
}

extension RateWindow {
    /// The usage level color, but at least orange while running ahead of the clock.
    func gaugeColor(now: Date) -> Color {
        let level = usedPercent / 100
        return isAheadOfPace(now: now) && level <= 0.65 ? .orange : Palette.level(level)
    }
}
