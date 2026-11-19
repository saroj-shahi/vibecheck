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
                if !sample.activeSessions.isEmpty {
                    NowSection(sessions: sample.activeSessions)
                }
                // Limits first: "how much is left" is what people open this for.
                ForEach(sample.agents) { AgentCard(summary: $0) }
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(text: "24 hours")
                        HourlyBars(values: sample.hourly, color: Palette.agents)
                            .frame(height: 44)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            SectionTitle(text: "7 days")
                            Spacer()
                            Text(Fmt.tokens(sample.week.total)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        DailyBars(values: sample.daily, color: Palette.agents)
                            .frame(height: 44)
                    }
                }
                if !sample.projectsToday.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionTitle(text: "Busiest projects today")
                        ForEach(sample.projectsToday.prefix(3), id: \.name) { project in
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
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(summary.agent.title).font(.system(size: 13, weight: .semibold))
                    .layoutPriority(1)
                if let name = summary.account.name {
                    Text("· \(name)").font(.system(size: 13)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                if let plan = summary.account.plan { PlanBadge(plan: plan) }
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    if summary.isWorking(now: context.date) { WorkingBadge() }
                }
                Spacer()
                Text(Fmt.tokens(summary.today.total)).font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            // The local estimate only when there's no real limit: its reset time is a guess and would
            // contradict the provider's own (seen in QA: "resets 5:00 PM" above "Resets in … (5:34 PM)").
            if let block = summary.block, !summary.limits.contains(where: { $0.windowMinutes == 300 }) {
                Text("5-hour window ≈ \(Fmt.tokens(block.tokens.total)) · resets ~\(block.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !summary.limits.isEmpty {
                // Ticks on its own so the countdown and pace marker move between scans.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(summary.limits.sorted { $0.windowMinutes < $1.windowMinutes }, id: \.key) {
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
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.cardTitle).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(limit.leftPercent.rounded()))% left")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }
            PaceBar(used: limit.usedPercent / 100, elapsed: limit.elapsedFraction(now: now), color: color)
                .frame(height: 12)
            HStack(alignment: .firstTextBaseline) {
                Text(resetText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if let burn = limit.burnText(now: now) {
                    Text(burn)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ahead ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
                        .help(ahead ? "At this pace it runs out before it resets" : "Average since this window started")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(limit.cardTitle): \(Int(limit.leftPercent.rounded())) percent left, resets in \(limit.countdown(now: now))\(ahead ? ", runs out before reset at this pace" : "")")
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
                    .frame(height: max(2, CGFloat(value / peak) * 44))
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

/// Green pulsing dot + "Working now" while an agent has written usage in the last two minutes.
private struct WorkingBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(.green).frame(width: 6, height: 6)
                .opacity(pulse ? 0.35 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            Text("Working now").font(.caption2.weight(.medium)).foregroundStyle(.green)
        }
        .onAppear { pulse = true }
        .accessibilityElement(children: .combine)
    }
}

/// Seven daily bars with weekday initials; today is the last, full-strength bar.
struct DailyBars: View {
    let values: [Double]
    let color: Color

    var body: some View {
        let peak = max(values.max() ?? 0, 1)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let day = calendar.date(byAdding: .day, value: index - (values.count - 1), to: today) ?? today
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(value > 0 ? color.opacity(index == values.count - 1 ? 1 : 0.6) : Color.secondary.opacity(0.2))
                        .frame(height: max(3, CGFloat(value / peak) * 30))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 9, weight: index == values.count - 1 ? .bold : .regular))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .help("\(day.formatted(.dateTime.weekday(.wide))): \(Fmt.tokens(Int(value)))")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tokens per day, last 7 days")
    }
}

/// Small capsule with the agent's plan ("Team", "Free", …).
private struct PlanBadge: View {
    let plan: String

    var body: some View {
        Text(plan)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .foregroundStyle(Palette.agents)
            .background(Capsule().fill(Palette.agents.opacity(0.16)))
            .fixedSize()
            .accessibilityLabel("\(plan) plan")
    }
}

/// Sessions running right now: project, model, tokens written, and how long it has been going.
private struct NowSection: View {
    let sessions: [ActiveSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle().fill(.green).frame(width: 6, height: 6)
                SectionTitle(text: "Now")
            }
            ForEach(sessions.prefix(3)) { session in
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(session.project).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Spacer()
                            Text(elapsed(since: session.started, now: context.date))
                                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Palette.agents)
                        }
                        Text("\(session.agent.title) · \(AgentNames.model(session.model)) · \(Fmt.tokens(session.tokens.output)) written")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(session.project), \(session.agent.title), running for \(elapsed(since: session.started, now: context.date))")
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.55)))
    }

    /// "3:57", "1:02:15".
    private func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
