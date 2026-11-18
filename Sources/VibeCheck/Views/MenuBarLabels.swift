import SwiftUI

/// The compact view drawn inside each status bar item, in the style chosen in Settings.
struct MenuBarLabel: View {
    let module: Module
    @Environment(SystemStats.self) private var stats
    @Environment(AppSettings.self) private var settings

    private var style: LabelStyle { settings.labelStyle(module) }
    private var colorful: Bool { settings.colorfulMenuBar }
    private let valueFont = Font.system(size: 11, weight: .medium).monospacedDigit()

    var body: some View {
        Group {
            switch module {
            case .cpu: meter(Fmt.percent(stats.cpu.total)) {
                MiniBars(totals: stats.cpuHistory.suffix(8), system: stats.cpuSystemHistory.suffix(8),
                         color: tint(Palette.user), systemColor: tint(Palette.system))
            }
            case .gpu: meter(Fmt.percent(stats.gpu.utilization)) {
                MiniBars(totals: stats.gpuHistory.suffix(8), system: [], color: tint(Palette.gpu))
            }
            case .memory: meter(Fmt.percent(stats.memory.usage)) { memoryGauge }
            case .network: rates(top: ("↑", stats.network.upload), bottom: ("↓", stats.network.download))
            case .disk: rates(top: ("R", stats.disk.readRate), bottom: ("W", stats.disk.writeRate))
            case .sensors: iconValue(stats.sensors.hottest.map { String(format: "%.0f°", $0) } ?? "–")
            case .battery: battery
            case .clock: clock
            }
        }
        .frame(width: settings.labelWidth(module), height: 22)
    }

    private func tint(_ color: Color) -> Color { colorful ? color : .primary }

    /// Graph-style modules: graph + value, icon + value, or value only.
    @ViewBuilder
    private func meter<Graph: View>(_ value: String, @ViewBuilder graph: () -> Graph) -> some View {
        HStack(spacing: 4) {
            switch style {
            case .standard: graph().frame(width: module == .memory ? 7 : 23, height: 15)
            case .iconAndValue: Image(systemName: module.symbol).font(.system(size: 12))
            case .valueOnly: EmptyView()
            }
            Text(value).font(valueFont).frame(minWidth: 30, alignment: .trailing)
        }
    }

    private var memoryGauge: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 1.5)
                .strokeBorder(.primary.opacity(0.5), lineWidth: 1)
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(tint(Palette.pressure(stats.memory.pressure)))
                        .frame(height: max(1, (geo.size.height - 2) * stats.memory.usage))
                        .padding(1)
                }
        }
    }

    private func rates(top: (String, Double), bottom: (String, Double)) -> some View {
        HStack(spacing: 3) {
            if style == .iconAndValue {
                Image(systemName: module.symbol).font(.system(size: 11))
            }
            VStack(alignment: .trailing, spacing: -2) {
                rateLine(top)
                rateLine(bottom)
            }
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
        }
    }

    private func rateLine(_ pair: (String, Double)) -> some View {
        HStack(spacing: 2) {
            Text(Fmt.compactRate(pair.1)).frame(maxWidth: .infinity, alignment: .trailing)
            if style == .standard { Text(pair.0).frame(width: 9) }
        }
    }

    private func iconValue(_ value: String) -> some View {
        HStack(spacing: 2) {
            if style != .valueOnly {
                Image(systemName: "thermometer.medium").font(.system(size: 12))
            }
            Text(value).font(valueFont).frame(minWidth: 28, alignment: .trailing)
        }
    }

    private var battery: some View {
        let b = stats.battery
        return HStack(spacing: 3) {
            if style != .valueOnly {
                Image(systemName: b.present ? batterySymbol(b) : "powerplug").font(.system(size: 13))
            }
            Text(b.present ? Fmt.percent(b.percent) : "AC").font(valueFont)
        }
    }

    private var clock: some View {
        HStack(spacing: 4) {
            if style == .iconAndValue {
                Image(systemName: "clock").font(.system(size: 12))
            }
            Text(ClockTicker.shared.now, format: settings.clockFormatStyle)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
        }
    }
}

func batterySymbol(_ b: BatterySample) -> String {
    if b.isCharging { return "battery.100percent.bolt" }
    switch b.percent {
    case ..<0.13: return "battery.0percent"
    case ..<0.38: return "battery.25percent"
    case ..<0.63: return "battery.50percent"
    case ..<0.88: return "battery.75percent"
    default: return "battery.100percent"
    }
}

/// Tiny history bars: total in `color` with the system share in `systemColor` at the bottom.
struct MiniBars: View {
    let totals: [Double]
    let system: [Double]
    var color: Color = Palette.user
    var systemColor: Color = Palette.system

    var body: some View {
        Canvas { context, size in
            let count = 8
            let barWidth: CGFloat = 2
            let gap = (size.width - barWidth * CGFloat(count)) / CGFloat(count - 1)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.primary.opacity(0.08)))
            let offset = count - totals.count
            for (i, total) in totals.enumerated() {
                let x = CGFloat(i + offset) * (barWidth + gap)
                let h = max(1, size.height * CGFloat(total))
                context.fill(Path(CGRect(x: x, y: size.height - h, width: barWidth, height: h)),
                             with: .color(color))
                let sys = i < system.count ? system[i] : 0
                let sh = size.height * CGFloat(min(sys, total))
                if sh > 0 {
                    context.fill(Path(CGRect(x: x, y: size.height - sh, width: barWidth, height: sh)),
                                 with: .color(systemColor.opacity(color == systemColor ? 0.6 : 1)))
                }
            }
        }
    }
}
