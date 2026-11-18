import SwiftUI

/// The compact view drawn inside each status bar item, in the style chosen in Settings.
/// Every number has a fixed width so the item's measured size never changes as values change.
struct MenuBarLabel: View {
    let module: Module
    /// Outer padding is skipped inside the combined item, which manages its own gaps.
    var padded = true
    @Environment(SystemStats.self) private var stats
    @Environment(AppSettings.self) private var settings

    /// Below this many bytes per second a direction counts as idle.
    static let activeThreshold: Double = 2048

    private var style: LabelStyle { settings.labelStyle(module) }
    private var gap: CGFloat { settings.menuBarSpacing.inner }
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
            case .network: network
            case .disk: rates(top: ("R", stats.disk.readRate, Palette.read),
                              bottom: ("W", stats.disk.writeRate, Palette.write), highlight: false)
            case .sensors: iconValue(stats.sensors.hottest.map { String(format: "%.0f°", $0) } ?? "–")
            case .battery: battery
            case .clock: clock
            case .weather: weather
            }
        }
        .frame(height: 22)
        .padding(.horizontal, padded ? settings.menuBarSpacing.padding : 0)
    }

    private func tint(_ color: Color) -> Color { settings.colorfulMenuBar ? color : .primary }

    private func value(_ text: String, width: CGFloat = 30) -> some View {
        Text(text).font(valueFont)
            .lineLimit(1).minimumScaleFactor(0.75)
            .frame(width: width, alignment: .trailing)
    }

    /// Graph-style modules: graph + value, icon + value, or value only.
    @ViewBuilder
    private func meter<Graph: View>(_ text: String, @ViewBuilder graph: () -> Graph) -> some View {
        HStack(spacing: gap) {
            switch style {
            case .standard: graph().frame(width: module == .memory ? 7 : 23, height: 15)
            case .iconAndValue: Image(systemName: module.symbol).font(.system(size: 12))
            case .valueOnly: EmptyView()
            }
            value(text)
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

    // MARK: Network: activity arrows light up while data moves; offline swaps in a clear indicator.

    private var network: some View {
        let offline = stats.network.interface == nil
        return ZStack {
            rates(top: ("↑", stats.network.upload, Palette.upload),
                  bottom: ("↓", stats.network.download, Palette.download), highlight: true)
                .opacity(offline ? 0 : 1)
            HStack(spacing: 2) {
                Image(systemName: "network.slash").font(.system(size: 10, weight: .semibold))
                Text("Offline").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .opacity(offline ? 1 : 0)
        }
        .help(offline ? "Offline" : "Network")
    }

    /// Two stacked rate lines. With `highlight`, each direction's arrow (or text) is colored while active
    /// and dimmed while idle.
    private func rates(top: (String, Double, Color), bottom: (String, Double, Color), highlight: Bool) -> some View {
        let anyActive = top.1 >= Self.activeThreshold || bottom.1 >= Self.activeThreshold
        return HStack(spacing: gap) {
            if style == .iconAndValue {
                Image(systemName: module.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(highlight && !anyActive ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            }
            VStack(alignment: .trailing, spacing: -2) {
                rateLine(top, highlight: highlight)
                rateLine(bottom, highlight: highlight)
            }
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
        }
    }

    private func rateLine(_ line: (label: String, rate: Double, color: Color), highlight: Bool) -> some View {
        let active = line.rate >= Self.activeThreshold
        return HStack(spacing: 1) {
            Text(Fmt.compactRate(line.rate))
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(width: 28, alignment: .trailing)
                .foregroundStyle(highlight && style == .valueOnly && !active ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            if style == .standard {
                Text(line.label)
                    .frame(width: 9)
                    .foregroundStyle(!highlight ? AnyShapeStyle(.primary)
                                     : active ? AnyShapeStyle(tint(line.color)) : AnyShapeStyle(.tertiary))
                    .fontWeight(highlight && active ? .heavy : .semibold)
            }
        }
    }

    private func iconValue(_ text: String) -> some View {
        HStack(spacing: gap) {
            if style != .valueOnly {
                Image(systemName: "thermometer.medium").font(.system(size: 12))
            }
            value(text, width: 27)
        }
    }

    private var battery: some View {
        let b = stats.battery
        return HStack(spacing: gap) {
            if style != .valueOnly {
                Image(systemName: b.present ? batterySymbol(b) : "powerplug").font(.system(size: 13))
            }
            value(b.present ? Fmt.percent(b.percent) : "AC")
        }
    }

    private var weather: some View {
        let forecast = WeatherStore.shared.forecast
        return HStack(spacing: gap) {
            if style != .valueOnly {
                Image(systemName: forecast.map { WeatherCode.symbol($0.code, isDay: $0.isDay) } ?? "cloud.sun")
                    .symbolRenderingMode(settings.colorfulMenuBar ? .multicolor : .monochrome)
                    .font(.system(size: 12))
                    .frame(width: 18)
            }
            value(forecast.map { String(format: "%.0f°", $0.temperature) } ?? "–", width: 27)
        }
    }

    private var clock: some View {
        HStack(spacing: gap) {
            if style == .iconAndValue {
                Image(systemName: "clock").font(.system(size: 12))
            }
            Text(ClockTicker.shared.now, format: settings.clockFormatStyle)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .lineLimit(1)
                .frame(width: settings.clockTextWidth, alignment: .center)
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
