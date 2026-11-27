import SwiftUI

struct MemoryPanel: View {
    @Environment(SystemStats.self) private var stats
    @State private var hoveredSegment: Int?

    var body: some View {
        let m = stats.memory
        let parts: [(name: String, bytes: Double, color: Color)] = [
            (String(localized: "App memory"), m.app, Palette.app),
            (String(localized: "Wired"), m.wired, Palette.wired),
            (String(localized: "Compressed"), m.compressed, Palette.compressed),
            (String(localized: "Cached files"), m.cached, Palette.cached),
        ]
        Panel(module: .memory, headline: Fmt.percent(m.usage),
              subtitle: String(localized: "\(Fmt.bytes(m.used)) of \(Fmt.bytes(m.total))")) {
            VStack(alignment: .leading, spacing: 6) {
                StackedBar(segments: parts.map { ($0.bytes, $0.color) },
                           total: m.total,
                           hoveredIndex: $hoveredSegment)
                HStack(spacing: 5) {
                    if let idx = hoveredSegment, parts.indices.contains(idx) {
                        let seg = parts[idx]
                        let share = m.total > 0 ? Fmt.percent(seg.bytes / m.total) : "0%"
                        Circle().fill(seg.color).frame(width: 7, height: 7)
                        Text("\(seg.name) · \(Fmt.bytes(seg.bytes)) (\(share))")
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    } else {
                        Circle().fill(Palette.pressure(m.pressure)).frame(width: 7, height: 7)
                        Text("Pressure \(m.pressure.label.lowercased())")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .animation(.easeOut(duration: 0.12), value: hoveredSegment)
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

