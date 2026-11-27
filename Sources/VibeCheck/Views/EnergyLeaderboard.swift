import AppKit
import SwiftUI

/// "Top battery drainers": the five apps that used the most energy today (or yesterday), all time counted.
struct EnergyLeaderboard: View {
    @Environment(SystemStats.self) private var stats
    @State private var day: EnergyLog.Day = .today

    var body: some View {
        let board = stats.energyLog.leaderboard(day)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle(text: day == .today ? "Energy used today" : "Energy used yesterday")
                Spacer()
                Picker("Day", selection: $day) {
                    Text("Today").tag(EnergyLog.Day.today)
                    Text("Yesterday").tag(EnergyLog.Day.yesterday)
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.mini).fixedSize()
            }
            if board.rows.isEmpty {
                Text(day == .today ? "Still collecting. Check back in a few minutes." : "Nothing recorded for yesterday.")
                    .font(.callout).foregroundStyle(.tertiary)
            } else {
                ForEach(board.rows) { row in
                    HStack(spacing: 6) {
                        Group {
                            if let agent = Self.agentKind(named: row.name) {
                                AgentLogoTile(agent: agent, size: 16)
                            } else if let icon = Self.icon(named: row.name) {
                                Image(nsImage: icon).resizable()
                            } else {
                                Image(systemName: "terminal").foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 16, height: 16)
                        Text(row.name).lineLimit(1).truncationMode(.tail)
                        Spacer()
                        Text(Fmt.percent(row.share)).foregroundStyle(.secondary).monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                        Text(EnergyLog.label(wattHours: row.wattHours)).monospacedDigit()
                            .frame(width: 66, alignment: .trailing)
                    }
                    .font(.callout)
                    .accessibilityElement(children: .combine)
                }
                Text("Counts all time since VibeCheck started watching, on battery or plugged in. Total \(EnergyLog.label(wattHours: board.total / 3600)).")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private static func icon(named name: String) -> NSImage? {
        NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.icon
    }

    /// Maps known local AI CLI binary names to their crisp AgentLogoTile artwork.
    nonisolated static func agentKind(named name: String) -> AgentKind? {
        let lower = name.trimmingCharacters(in: .whitespaces).lowercased()
        switch lower {
        case "claude", "claude-code": return .claude
        case "codex": return .codex
        case "opencode": return .opencode
        case "copilot", "github-copilot": return .copilot
        case "agy", "antigravity": return .antigravity
        default: return nil
        }
    }
}
