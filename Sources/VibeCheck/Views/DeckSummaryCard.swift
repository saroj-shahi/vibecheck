import SwiftUI

/// The four facts on the deck home's summary card, built from readings the app already has.
enum DeckFacts {
    enum Kind: String, CaseIterable {
        case uptime, topApp, energy, limit
    }

    struct Fact: Identifiable, Equatable {
        let kind: Kind
        let title: String
        let value: String
        let detail: String?
        let module: Module
        var id: Kind { kind }

        var spoken: String { detail.map { "\(title): \(value), \($0)" } ?? "\(title): \(value)" }
        var symbol: String {
            switch kind {
            case .uptime: "clock.arrow.circlepath"
            case .topApp: "flame"
            case .energy: "bolt"
            case .limit: "gauge.with.dots.needle.33percent"
            }
        }
    }

    /// The limit with the least left across every agent; ties go to the one that resets first.
    nonisolated static func tightestLimit(_ agents: [AgentSummary]) -> (agent: AgentKind, window: RateWindow)? {
        var best: (agent: AgentKind, window: RateWindow)?
        for summary in agents {
            for window in summary.limits {
                guard let current = best else { best = (summary.agent, window); continue }
                let left = window.leftPercent, bestLeft = current.window.leftPercent
                if left < bestLeft || (left == bestLeft && window.resetsAt < current.window.resetsAt) {
                    best = (summary.agent, window)
                }
            }
        }
        return best
    }

    /// Cuts a long name with "…" so the number beside it always shows.
    nonisolated static func shortName(_ name: String, max: Int) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > max, max > 1 else { return trimmed }
        return String(trimmed.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The facts that have data, in card order. An empty list hides the card.
    nonisolated static func facts(uptime: TimeInterval,
                                  topApp: (name: String, cpu: Double)?,
                                  energyLeader: (name: String, wattHours: Double)?,
                                  limit: (agent: AgentKind, window: RateWindow)?,
                                  now: Date = Date()) -> [Fact] {
        var facts: [Fact] = []
        if uptime >= 60 {
            let boot = now.addingTimeInterval(-uptime)
            facts.append(Fact(kind: .uptime, title: String(localized: "Uptime"), value: Fmt.uptime(uptime),
                              detail: String(localized: "Since \(boot.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"),
                              module: .cpu))
        }
        if let topApp, !topApp.name.isEmpty, topApp.cpu >= 1 {
            facts.append(Fact(kind: .topApp, title: String(localized: "Top app now"), value: shortName(topApp.name, max: 20),
                              detail: String(localized: "\(TileContent.cpuText(topApp.cpu)) CPU"), module: .cpu))
        }
        if let energyLeader, !energyLeader.name.isEmpty, energyLeader.wattHours > 0 {
            facts.append(Fact(kind: .energy, title: String(localized: "Energy leader today"),
                              value: shortName(energyLeader.name, max: 20),
                              detail: String(localized: "\(EnergyLog.label(wattHours: energyLeader.wattHours)) so far"),
                              module: .battery))
        }
        if let limit {
            let window = limit.window
            let detail = window.runsOutAt(now: now).map {
                String(localized: "\(window.title), runs out ~\(window.runOutTimeText($0, now: now))")
            } ?? "\(limit.agent.title), \(window.title)"
            facts.append(Fact(kind: .limit, title: String(localized: "Tightest limit"),
                              value: String(localized: "\(Fmt.percent(window.leftPercent / 100)) left"),
                              detail: detail, module: .agents))
        }
        return facts
    }
}

/// Full-width card under the quick toggles: uptime, the app working hardest, today's energy leader and the
/// agent limit closest to running out. Each fact opens its module.
struct DeckSummaryCard: View {
    @Environment(DeckModel.self) private var model
    @Environment(SystemStats.self) private var stats

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .topLeading), count: 2)

    var body: some View {
        let top = stats.topApps(by: \.cpu, limit: 1).first
        let leader = stats.energyLog.leaderboard(.today, limit: 1).rows.first
        let facts = DeckFacts.facts(uptime: stats.uptime,
                                    topApp: top.map { ($0.name, $0.cpu) },
                                    energyLeader: leader.map { ($0.name, $0.wattHours) },
                                    limit: DeckFacts.tightestLimit(AgentUsageStore.shared.sample.agents))
        if !facts.isEmpty {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(facts) { fact in
                    SummaryFactCell(fact: fact, opens: model.modules.contains(fact.module)) {
                        model.go(.module(fact.module))
                    }
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.quaternary.opacity(0.55))
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Summary")
        }
    }
}

private struct SummaryFactCell: View {
    let fact: DeckFacts.Fact
    /// False when the fact's module is turned off: then there's no panel to open.
    let opens: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: fact.symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 11)
                    Text(fact.title)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                Text(fact.value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
                Text(fact.detail ?? " ")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(hovering && opens ? 0.9 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(TilePressStyle())
        .disabled(!opens)
        .onHover { hovering in withAnimation(.easeOut(duration: hovering ? 0.15 : 0.12)) { self.hovering = hovering } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fact.spoken)
        .accessibilityAddTraits(opens ? .isButton : [])
        .accessibilityHint(opens ? Text("Shows \(fact.module.title) details") : Text(""))
        .help(opens ? Text("\(fact.module.title) — click for details") : Text(fact.spoken))
    }
}
