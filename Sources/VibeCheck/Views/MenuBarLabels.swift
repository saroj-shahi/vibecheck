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
    private var options: ItemOptions { settings.options(module) }
    private var gap: CGFloat { settings.menuBar.spacing.inner }
    private let valueFont = Font.system(size: 11, weight: .medium).monospacedDigit()
    /// Item icons and graphs harmonize with macOS menu bar glyphs and the vibe ring.
    static let iconSize: CGFloat = 14.5
    static let graphHeight: CGFloat = 16
    private let iconFont = Font.system(size: MenuBarLabel.iconSize)
    private var showsIcon: Bool { style == .iconAndValue || style == .iconValueArrows }
    private var showsArrows: Bool { style == .standard || style == .iconValueArrows }

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
            case .memory: meter(memoryText, width: options.memoryValue == .percent ? 30 : 36) { memoryGauge }
            case .network: network
            case .disk: disk
            case .sensors: iconValue(stats.sensors.hottest.map { String(format: "%.0f°", temperature($0)) } ?? "–")
            case .battery: battery
            case .clock: clock
            case .weather: weather
            case .agents: agents
            case .todo: todo
            }
        }
        .frame(height: 22)
        .padding(.horizontal, padded ? settings.menuBar.spacing.padding : 0)
    }

    private func tint(_ color: Color) -> Color { settings.menuBar.colorful ? color : .primary }

    private func value(_ text: String, width: CGFloat = 30) -> some View {
        Text(text).font(valueFont)
            .lineLimit(1).minimumScaleFactor(0.75)
            .frame(width: width, alignment: .trailing)
    }

    /// Graph-style modules: graph + value, icon + value, or value only.
    @ViewBuilder
    private func meter<Graph: View>(_ text: String, width: CGFloat = 30, @ViewBuilder graph: () -> Graph) -> some View {
        HStack(spacing: gap) {
            switch style {
            case .standard: graph().frame(width: module == .memory ? 7 : 23, height: Self.graphHeight)
            case .iconAndValue, .iconValueArrows: Image(systemName: module.symbol).font(iconFont)
            case .valueOnly, .limits, .calendarIcon, .calendarIconOnly: EmptyView()
            }
            value(text, width: width)
        }
    }

    private var memoryText: String {
        let m = stats.memory
        switch options.memoryValue {
        case .percent: return Fmt.percent(m.usage)
        case .used: return Fmt.compactBytes(m.used)
        case .free: return Fmt.compactBytes(max(0, m.total - m.used))
        }
    }

    private func temperature(_ celsius: Double) -> Double {
        options.sensorUnit == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    @ViewBuilder
    private var disk: some View {
        if options.diskValue == .free {
            let volume = stats.volumes.first { $0.path == "/" } ?? stats.volumes.first
            HStack(spacing: gap) {
                if style != .valueOnly { Image(systemName: "internaldrive").font(iconFont) }
                value(volume.map { Fmt.compactBytes($0.available) } ?? "–", width: 36)
            }
            .help("Startup disk free space")
        } else {
            rates(top: ("R", stats.disk.readRate, Palette.read),
                  bottom: ("W", stats.disk.writeRate, Palette.write), highlight: false)
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
            Group {
                switch options.networkDirections {
                case .both:
                    rates(top: ("↑", stats.network.upload, Palette.upload),
                          bottom: ("↓", stats.network.download, Palette.download), highlight: true)
                case .download: singleRate(("↓", stats.network.download, Palette.download))
                case .upload: singleRate(("↑", stats.network.upload, Palette.upload))
                }
            }
            .opacity(offline ? 0 : 1)
            HStack(spacing: 2) {
                Image(systemName: "network.slash").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.red)
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
            if showsIcon {
                if module == .network {
                    networkGlobe(active: anyActive)
                } else {
                    Image(systemName: module.symbol).font(iconFont)
                }
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
            if showsArrows {
                Text(line.label)
                    .frame(width: 9)
                    .foregroundStyle(!highlight ? AnyShapeStyle(.primary)
                                     : active ? AnyShapeStyle(tint(line.color)) : AnyShapeStyle(.tertiary))
                    .fontWeight(highlight && active ? .heavy : .semibold)
            }
        }
    }

    /// The network glyph, colored by status instead of a dot: green while online (full while data moves,
    /// softer while idle), red while offline.
    private func networkGlobe(active: Bool) -> some View {
        let online = stats.network.interface != nil
        return Image(systemName: module.symbol)
            .font(iconFont)
            .foregroundStyle(online ? Color.green.opacity(active ? 1 : 0.55) : Color.red)
            .accessibilityLabel(online ? "Online" : "Offline")
    }

    /// One direction, one line, at the normal value size.
    private func singleRate(_ line: (label: String, rate: Double, color: Color)) -> some View {
        let active = line.rate >= Self.activeThreshold
        return HStack(spacing: gap) {
            if showsIcon { networkGlobe(active: active) }
            value(Fmt.compactRate(line.rate), width: 34)
            if showsArrows {
                Text(line.label).font(.system(size: 11, weight: active ? .heavy : .semibold))
                    .foregroundStyle(active ? AnyShapeStyle(tint(line.color)) : AnyShapeStyle(.tertiary))
            }
        }
    }

    private func iconValue(_ text: String) -> some View {
        HStack(spacing: gap) {
            if style != .valueOnly {
                Image(systemName: "thermometer.medium").font(iconFont)
            }
            value(text, width: 27)
        }
    }

    private var battery: some View {
        let b = stats.battery
        return HStack(spacing: gap) {
            if style != .valueOnly {
                Image(systemName: b.present ? batterySymbol(b) : "powerplug").font(iconFont)
            }
            if !b.present {
                value("AC")
            } else {
                let time = b.minutesRemaining.map(Fmt.clockDuration) ?? "–:––"
                switch options.batteryValue {
                case .percent: value(Fmt.percent(b.percent))
                case .time: value(time, width: 34)
                case .both:
                    VStack(alignment: .trailing, spacing: -2) {
                        Text(Fmt.percent(b.percent))
                        Text(time).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .frame(width: 28, alignment: .trailing)
                }
            }
        }
    }

    private var weather: some View {
        let forecast = WeatherStore.shared.forecast
        return HStack(spacing: gap) {
            if style != .valueOnly {
                Image(systemName: forecast.map { WeatherCode.symbol($0.code, isDay: $0.isDay) } ?? "cloud.sun")
                    .symbolRenderingMode(settings.menuBar.colorful ? .multicolor : .monochrome)
                    .font(iconFont)
                    .frame(width: 22)
            }
            value(forecast.map { String(format: "%.0f°", $0.temperature) } ?? "–", width: 27)
        }
    }

    /// Checklist icon and the open count ("99+" at most, so the measured width holds). The icon takes the
    /// accent while something is overdue or due today. Never asks for Reminders access itself.
    private var todo: some View {
        let store = RemindersStore.shared
        let ready = store.access == .granted && store.loaded
        return HStack(spacing: gap) {
            if style != .valueOnly {
                Image(systemName: Module.todo.symbol).font(iconFont)
                    .foregroundStyle(ready && store.dueNowCount > 0 ? tint(Module.todo.accent) : .primary)
            }
            value(ready ? TodoLogic.countLabel(store.open.count) : "–", width: 24)
        }
        .task { store.ensureStarted() }
    }

    /// Limits keep one width in every state (loading, estimate, limits): the status item's length is only
    /// measured when it's created or settings change, so it must not grow later.
    static let limitsWidth: CGFloat = 104
    static let limitsWidthNoReset: CGFloat = 52

    @ViewBuilder
    private var agents: some View {
        let options = self.options
        if options.agentValue.isLimits {
            agentsContent(options)
                .frame(width: options.agentShowReset ? Self.limitsWidth : Self.limitsWidthNoReset, alignment: .leading)
        } else {
            agentsContent(options)
        }
    }

    @ViewBuilder
    private func agentsContent(_ options: ItemOptions) -> some View {
        let showIcon = style != .valueOnly
        let sample = AgentUsageStore.shared.sample
        let agent = sample.menuBarAgent(options)
        switch sample.menuBarContent(options) {
        case .limits(let limits, let used):
            AgentLimitsLabel(limits: limits, tint: tint(agent.brandColor), agent: agent, used: used,
                             showReset: options.agentShowReset, showRunOut: options.agentShowRunOut, showIcon: showIcon)
        case .windowEstimate(let estAgent, let block, let today) where options.agentShowReset:
            WindowEstimateLabel(agent: estAgent, block: block, today: today, tint: tint(estAgent.brandColor), showIcon: showIcon)
        case .windowEstimate(_, _, let today):
            agentTokens(today, agent: agent, showIcon: showIcon)
        case .tokens(let total):
            agentTokens(total, agent: agent, showIcon: showIcon)
        }
    }

    private func agentTokens(_ total: Int, agent: AgentKind, showIcon: Bool) -> some View {
        HStack(spacing: gap) {
            if showIcon {
                AgentLogo(agent: agent, size: MenuBarLabel.graphHeight).foregroundStyle(tint(agent.brandColor))
            }
            value(AgentUsageStore.shared.sample.scanned ? Fmt.tokens(total) : "–", width: 34)
        }
    }

    private var clock: some View {
        let now = ClockTicker.shared.now
        let pinned = settings.clock.menuBarWorldClocks
        return HStack(spacing: gap) {
            if style == .iconAndValue {
                Image(systemName: "clock").font(iconFont)
            } else if style == .calendarIcon || style == .calendarIconOnly {
                CalendarDayIcon(date: now, style: settings.clock.calendarIconStyle)
            }
            if style != .calendarIconOnly {
                Text(now, format: settings.clock.formatStyle)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .lineLimit(1)
                    .frame(width: settings.clock.textWidth, alignment: .center)
            }
            if !pinned.isEmpty {
                ForEach(pinned) { world in
                    Text("\(world.menuBarTag) \(world.formattedTime(at: now))")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: settings.clock.worldClockWidth(for: world), alignment: .center)
                }
            }
        }
    }
}

/// Crisp monochrome mini calendar icon displaying date, weekday & date, week & date, or week number.
struct CalendarDayIcon: View {
    let date: Date
    var style: CalendarIconStyle = .day

    private var dayNumber: Int { Calendar.current.component(.day, from: date) }
    private var weekNumber: Int { CalendarDateHelper.weekNumber(for: date) }
    private var shortWeekday: String {
        let df = DateFormatter()
        df.locale = .current
        df.dateFormat = "EEE"
        return String(df.string(from: date).prefix(3)).uppercased()
    }

    private var iconWidth: CGFloat {
        switch style {
        case .day: 16
        case .weekdayAndDay: 21
        case .weekAndDay, .week: 23
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch style {
            case .day:
                Rectangle()
                    .fill(.primary)
                    .frame(height: 3.5)
                Text("\(dayNumber)")
                    .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .weekdayAndDay:
                ZStack {
                    Rectangle().fill(.primary)
                    Text(shortWeekday)
                        .font(.system(size: 5.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(.background)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(height: 6.5)
                Text("\(dayNumber)")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .weekAndDay:
                ZStack {
                    Rectangle().fill(.primary)
                    Text("W\(weekNumber)")
                        .font(.system(size: 5.5, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.background)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(height: 6.5)
                Text("\(dayNumber)")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .week:
                Rectangle()
                    .fill(.primary)
                    .frame(height: 3.5)
                Text("W\(weekNumber)")
                    .font(.system(size: 8, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: iconWidth, height: 16.5)
        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .strokeBorder(.primary, lineWidth: 1.1)
        )
        .accessibilityHidden(true)
    }
}

/// Small status dot pinned to the bottom-trailing corner of the network glyph:
/// green while an interface is up, red while offline.
struct NetworkStatusDot: ViewModifier {
    let online: Bool
    let size: CGFloat
    let enabled: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            if enabled {
                Circle()
                    .fill(online ? Color.green : Color.red)
                    .frame(width: size, height: size)
                    .offset(x: size * 0.35, y: size * 0.25)
                    .accessibilityLabel(online ? "Online" : "Offline")
            }
        }
    }
}

extension View {
    func networkStatusDot(online: Bool, size: CGFloat = 5, enabled: Bool = true) -> some View {
        modifier(NetworkStatusDot(online: online, size: size, enabled: enabled))
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
            let well = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2.5)
            context.fill(well, with: .color(.primary.opacity(0.07)))
            context.stroke(well, with: .color(.primary.opacity(0.12)), lineWidth: 0.5)
            let offset = count - totals.count
            for (i, total) in totals.enumerated() {
                let x = CGFloat(i + offset) * (barWidth + gap)
                let h = max(1, (size.height - 2) * CGFloat(total))
                let barRect = CGRect(x: x, y: size.height - 1 - h, width: barWidth, height: h)
                context.fill(Path(roundedRect: barRect, cornerRadius: 0.75), with: .color(color))
                let sys = i < system.count ? system[i] : 0
                let sh = (size.height - 2) * CGFloat(min(sys, total))
                if sh > 0 {
                    let sysRect = CGRect(x: x, y: size.height - 1 - sh, width: barWidth, height: sh)
                    context.fill(Path(roundedRect: sysRect, cornerRadius: 0.5),
                                 with: .color(systemColor.opacity(color == systemColor ? 0.6 : 1)))
                }
            }
        }
    }
}

/// Two stacked rows ("49% ↻ 2h 42m" over "68% ↻ 5d 22h"): percent left and time to reset, shortest window first.
/// Falls back to tokens in `MenuBarLabel` when no agent reports limits.
struct AgentLimitsLabel: View {
    let limits: [RateWindow]
    let tint: Color
    var agent: AgentKind = .claude
    /// Show "% used" instead of "% left".
    var used = false
    var showReset = true
    /// Swap the countdown for the run-out time (same slot, so the width never changes) while the limit would run out.
    var showRunOut = false
    var showIcon = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 4) {
                if showIcon { AgentLogo(agent: agent, size: MenuBarLabel.graphHeight).foregroundStyle(tint) }
                VStack(alignment: .trailing, spacing: -1) {
                    ForEach(limits.prefix(2), id: \.key) { limit in
                        HStack(spacing: 3) {
                            Text("\(Int((used ? min(max(limit.usedPercent, 0), 100) : limit.leftPercent).rounded()))%")
                                .frame(width: 30, alignment: .trailing)
                                .foregroundStyle(limit.isAheadOfPace(now: context.date)
                                                 ? AnyShapeStyle(limit.gaugeColor(now: context.date)) : AnyShapeStyle(.primary))
                            if showReset {
                                if showRunOut, let out = limit.runsOutAt(now: context.date) {
                                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 7, weight: .bold))
                                    Text(limit.runOutShortText(out, now: context.date)).frame(width: 44, alignment: .leading)
                                } else {
                                    Image(systemName: "arrow.clockwise").font(.system(size: 7, weight: .bold))
                                    Text(limit.countdown(now: context.date)).frame(width: 44, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(agent.title + ": " + limits.prefix(2).map {
                used ? String(localized: "\($0.cardTitle) \(Int($0.usedPercent.rounded())) percent used")
                     : String(localized: "\($0.cardTitle) \(Int($0.leftPercent.rounded())) percent left") }
                .joined(separator: ", "))
        }
    }
}

/// "Limits left" without live limits: an agent's tokens in the estimated 5-hour window with its reset
/// countdown, over today's total.
struct WindowEstimateLabel: View {
    let agent: AgentKind
    let block: UsageBlock
    let today: Int
    let tint: Color
    var showIcon = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let reset = RateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: block.end).countdown(now: context.date)
            HStack(spacing: 4) {
                if showIcon { AgentLogo(agent: agent, size: MenuBarLabel.graphHeight).foregroundStyle(tint) }
                VStack(alignment: .trailing, spacing: -1) {
                    HStack(spacing: 3) {
                        Text(Fmt.tokens(block.tokens.total)).frame(width: 30, alignment: .trailing)
                        Image(systemName: "arrow.clockwise").font(.system(size: 7, weight: .bold))
                        Text(reset).frame(width: 44, alignment: .leading)
                    }
                    HStack(spacing: 3) {
                        Text(Fmt.tokens(today)).frame(width: 30, alignment: .trailing)
                        Text("today").foregroundStyle(.secondary).frame(width: 54, alignment: .leading)
                    }
                }
                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(agent.title): \(Fmt.tokens(block.tokens.total)) tokens this 5-hour window, resets in \(reset). \(Fmt.tokens(today)) today")
        }
    }
}
