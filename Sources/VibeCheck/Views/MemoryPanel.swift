import SwiftUI

struct MemoryPanel: View {
    @Environment(SystemStats.self) private var stats

    var body: some View {
        let m = stats.memory
        Panel(module: .memory, headline: Fmt.percent(m.usage),
              subtitle: String(localized: "\(Fmt.bytes(m.used)) of \(Fmt.bytes(m.total))")) {
            VStack(alignment: .leading, spacing: 6) {
                StackedBar(segments: [(m.app, Palette.app), (m.wired, Palette.wired),
                                      (m.compressed, Palette.compressed), (m.cached, Palette.cached)],
                           total: m.total)
                HStack(spacing: 5) {
                    Circle().fill(Palette.pressure(m.pressure)).frame(width: 7, height: 7)
                    Text("Pressure \(m.pressure.label.lowercased())")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            MetricChart(lines: [.init(key: .memory, color: Palette.app)], maxValue: 1, height: 64, format: Fmt.percent)

            ProcessList(metric: .memory)

            DetailsDisclosure(.memory) {
                VStack(spacing: 4) {
                    StatRow(label: "App memory", value: Fmt.bytes(m.app), color: Palette.app)
                    StatRow(label: "Wired", value: Fmt.bytes(m.wired), color: Palette.wired)
                    StatRow(label: "Compressed", value: Fmt.bytes(m.compressed), color: Palette.compressed)
                    StatRow(label: "Cached files", value: Fmt.bytes(m.cached), color: Palette.cached)
                    StatRow(label: "Free", value: Fmt.bytes(m.free))
                    StatRow(label: "Swap used",
                            value: m.swapTotal > 0 ? String(localized: "\(Fmt.bytes(m.swapUsed)) of \(Fmt.bytes(m.swapTotal))") : String(localized: "None"))
                }
            }
        }
    }
}

