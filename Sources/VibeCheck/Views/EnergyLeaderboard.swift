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
                            if let icon = Self.icon(named: row.name) {
                                Image(nsImage: icon).resizable()
                            } else {
                                Image(systemName: "app").foregroundStyle(.secondary)
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
}
