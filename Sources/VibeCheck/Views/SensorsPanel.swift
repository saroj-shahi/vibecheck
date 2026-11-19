import SwiftUI

struct SensorsPanel: View {
    @Environment(SystemStats.self) private var stats

    var body: some View {
        let s = stats.sensors
        Panel(module: .sensors, headline: s.hottest.map(celsius) ?? "—", subtitle: fanSummary(s)) {
            if s.summary.isEmpty && s.fans.isEmpty {
                Text("No sensors available on this Mac.").font(.callout).foregroundStyle(.secondary)
            }
            if s.hottest != nil {
                MetricChart(lines: [.init(key: .temperature, color: .orange)], maxValue: 105, height: 80,
                            format: { String(format: "%.0f °C", $0) })
            }
            if !s.summary.isEmpty {
                VStack(spacing: 4) {
                    ForEach(s.summary) { t in
                        StatRow(label: LocalizedStringKey(t.name), value: celsius(t.celsius), color: Palette.temperature(t.celsius))
                    }
                }
            }

            DetailsDisclosure(.sensors) {
                if !s.fans.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(text: s.fans.count == 1 ? "Fan" : "Fans")
                        ForEach(s.fans) { fan in
                            StatRow(label: s.fans.count == 1 ? "Speed" : "Fan \(fan.id + 1)",
                                    value: fan.rpm < 1 ? String(localized: "Off") : String(localized: "\(String(Int(fan.rpm.rounded()))) rpm"))
                            CapacityBar(fraction: fan.level, color: .cyan)
                            if let lo = fan.minRPM, let hi = fan.maxRPM {
                                Text(String(localized: "Range \(String(Int(lo.rounded())))–\(String(Int(hi.rounded()))) rpm")).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                if s.systemPower != nil || s.adapterPower != nil {
                    VStack(spacing: 4) {
                        SectionTitle(text: "Power").frame(maxWidth: .infinity, alignment: .leading)
                        if let w = s.systemPower { StatRow(label: "System total", value: String(format: "%.1f W", w)) }
                        if let w = s.adapterPower { StatRow(label: "From power adapter", value: String(format: "%.1f W", w)) }
                    }
                }
                if s.all.count > s.summary.count {
                    VStack(spacing: 3) {
                        SectionTitle(text: "All sensors (\(s.all.count))").frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(s.all) { t in StatRow(label: LocalizedStringKey(t.name), value: celsius(t.celsius)) }
                    }
                }
            }
        }
    }

    private func fanSummary(_ s: SensorsSample) -> String? {
        guard let fan = s.fans.first else { return nil }
        return fan.rpm < 1 ? String(localized: "Fan off") : String(localized: "Fan \(String(Int(fan.rpm.rounded()))) rpm")
    }

    private func celsius(_ value: Double) -> String { String(format: "%.0f °C", value) }
}

