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
                Text("No agent logs found on this Mac. VibeCheck reads Claude Code (~/.claude) and Codex (~/.codex) usage.")
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
            ForEach(summary.limits, id: \.windowMinutes) { limit in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(limit.title).font(.caption)
                        Spacer()
                        Text("\(Int(limit.usedPercent.rounded()))% used · resets \(resetText(limit.resetsAt))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(max(limit.usedPercent / 100, 0), 1))
                        .tint(Palette.level(limit.usedPercent / 100))
                }
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

    private func resetText(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day())
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
