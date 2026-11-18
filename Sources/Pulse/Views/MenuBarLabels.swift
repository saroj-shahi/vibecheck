import SwiftUI

/// The compact view drawn inside each status bar item.
struct MenuBarLabel: View {
    let module: Module
    @Environment(SystemStats.self) private var stats

    var body: some View {
        Group {
            switch module {
            case .cpu: cpu
            case .gpu: gpu
            case .memory: memory
            case .network: twoLine(top: ("↑", Fmt.compactRate(stats.network.upload)),
                                   bottom: ("↓", Fmt.compactRate(stats.network.download)))
            case .disk: twoLine(top: ("R", Fmt.compactRate(stats.disk.readRate)),
                                bottom: ("W", Fmt.compactRate(stats.disk.writeRate)))
            case .sensors: sensors
            case .battery: battery
            }
        }
        .frame(width: module.labelWidth, height: 22)
    }

    private var cpu: some View {
        HStack(spacing: 4) {
            MiniBars(totals: stats.cpuHistory.suffix(8), system: stats.cpuSystemHistory.suffix(8))
                .frame(width: 23, height: 15)
            Text(Fmt.percent(stats.cpu.total))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var gpu: some View {
        HStack(spacing: 4) {
            MiniBars(totals: stats.gpuHistory.suffix(8), system: [], color: Palette.gpu)
                .frame(width: 23, height: 15)
            Text(Fmt.percent(stats.gpu.utilization))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var memory: some View {
        HStack(spacing: 4) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 1.5)
                    .strokeBorder(.primary.opacity(0.5), lineWidth: 1)
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Palette.pressure(stats.memory.pressure))
                            .frame(height: max(1, (geo.size.height - 2) * stats.memory.usage))
                            .padding(1)
                    }
            }
            .frame(width: 7, height: 15)
            Text(Fmt.percent(stats.memory.usage))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var sensors: some View {
        HStack(spacing: 2) {
            Image(systemName: "thermometer.medium").font(.system(size: 12))
            Text(stats.sensors.hottest.map { String(format: "%.0f°", $0) } ?? "–")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .frame(width: 28, alignment: .trailing)
        }
    }

    private var battery: some View {
        let b = stats.battery
        return HStack(spacing: 3) {
            Image(systemName: b.present ? batterySymbol(b) : "powerplug")
                .font(.system(size: 13))
            if b.present {
                Text(Fmt.percent(b.percent))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
            } else {
                Text("AC").font(.system(size: 11, weight: .medium))
            }
        }
    }

    private func twoLine(top: (String, String), bottom: (String, String)) -> some View {
        VStack(alignment: .trailing, spacing: -2) {
            line(top)
            line(bottom)
        }
        .font(.system(size: 9, weight: .semibold).monospacedDigit())
    }

    private func line(_ pair: (String, String)) -> some View {
        HStack(spacing: 2) {
            Text(pair.1).frame(maxWidth: .infinity, alignment: .trailing)
            Text(pair.0).frame(width: 9)
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

/// Tiny CPU history bars: total in blue with the system share in red at the bottom.
struct MiniBars: View {
    let totals: [Double]
    let system: [Double]
    var color: Color = Palette.user

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
                                 with: .color(Palette.system))
                }
            }
        }
    }
}
