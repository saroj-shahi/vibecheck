import SwiftUI

extension EnvironmentValues {
    /// Shared namespace so tiles and detail headers can morph into each other.
    @Entry var deckNamespace: Namespace.ID? = nil
    /// True inside the deck's detail view; shows a back chevron in the panel header.
    @Entry var deckShowsBack = false
}

private struct DeckHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    /// `matchedGeometryEffect` only when a deck namespace is present (panels are also used outside the deck).
    @ViewBuilder
    func deckMatched(_ id: String, _ namespace: Namespace.ID?) -> some View {
        if let namespace { matchedGeometryEffect(id: id, in: namespace) } else { self }
    }
}

/// Root of the deck window: home grid or one module's detail, reporting its natural height so the
/// window can resize around it.
struct DeckRoot: View {
    let onHeight: (CGFloat) -> Void
    @Environment(DeckModel.self) private var model
    @Namespace private var namespace

    var body: some View {
        ScrollView(.vertical) {
            Group {
                switch model.route {
                case .home:
                    DeckHome()
                case .module(let module):
                    ModulePanel(module: module)
                        .environment(\.deckShowsBack, true)
                        .transition(.opacity)
                }
            }
            .environment(\.deckNamespace, namespace)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: DeckHeightKey.self, value: proxy.size.height)
            })
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.automatic)
        .frame(width: Deck.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(DeckHeightKey.self) { height in
            MainActor.assumeIsolated { onHeight(height) }
        }
    }
}

// MARK: - Home

struct DeckHome: View {
    @Environment(DeckModel.self) private var model
    @Environment(SystemStats.self) private var stats

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: Deck.columns)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(model.modules.enumerated()), id: \.element) { index, module in
                    ModuleTile(module: module,
                               focused: model.keyboardFocusVisible && model.focusIndex == index) {
                        model.go(.module(module))
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96))
                            .animation(Deck.animation.delay(model.staggerDelay(for: index))),
                        removal: .opacity.combined(with: .scale(scale: 0.96))
                            .animation(Deck.animation.delay(model.staggerDelay(for: index) * 0.5))))
                }
            }
        }
        .padding(16)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.mint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.mint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text("VibeCheck").font(.system(size: 13, weight: .semibold))
                Text("Up \(Fmt.uptime(stats.uptime)) · ⌘1–9 to jump")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            DeckIconButton(symbol: "gearshape", help: "Settings (⌘,)") {
                (NSApp.delegate as? AppDelegate)?.showSettings()
            }
            DeckIconButton(symbol: "power", help: "Quit VibeCheck") { NSApp.terminate(nil) }
        }
    }
}

/// 26-pt circular icon button with a hover fill, used in deck headers.
struct DeckIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.quaternary.opacity(hovering ? 1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering } }
    }
}

// MARK: - Tiles

struct ModuleTile: View {
    let module: Module
    let focused: Bool
    let action: () -> Void
    @Environment(\.deckNamespace) private var namespace
    @Environment(SystemStats.self) private var stats
    @Environment(AppSettings.self) private var settings
    @State private var hovering = false

    var body: some View {
        let content = TileContent.make(module, stats: stats, settings: settings)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: module.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(module.accent)
                        .deckMatched("icon.\(module.rawValue)", namespace)
                    Text(module.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(content.value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                    .tracking(-0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .deckMatched("value.\(module.rawValue)", namespace)
                Group {
                    if let values = content.spark {
                        Sparkline(values: values, color: module.accent, maxValue: content.sparkMax)
                    } else if let detail = content.detail {
                        Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(height: 16)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.quaternary.opacity(hovering ? 0.9 : 0.55))
                    .deckMatched("bg.\(module.rawValue)", namespace)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(focused ? 1 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(TilePressStyle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering } }
        .accessibilityLabel("\(module.title), \(content.spoken)")
        .accessibilityHint("Shows \(module.title) details")
        .help("\(module.title) — click for details")
    }
}

/// Press feedback: a quick 3% scale-down that springs back on release.
struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Deck.reduceMotion ? 0.97 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// What a tile shows for each module.
struct TileContent {
    var value: String
    var detail: String?
    var spark: [Double]?
    var sparkMax: Double?
    var spoken: String

    @MainActor
    static func make(_ module: Module, stats: SystemStats, settings: AppSettings) -> TileContent {
        func recent(_ key: HistoryKey) -> [Double] { Array(stats.live(key).suffix(30)) }
        switch module {
        case .cpu:
            let v = Fmt.percent(stats.cpu.total)
            return TileContent(value: v, spark: recent(.cpu), sparkMax: 1, spoken: "\(v) in use")
        case .gpu:
            guard !stats.gpu.gpus.isEmpty else { return TileContent(value: "—", detail: "No GPU stats", spoken: "unavailable") }
            let v = Fmt.percent(stats.gpu.utilization)
            return TileContent(value: v, spark: recent(.gpu), sparkMax: 1, spoken: "\(v) in use")
        case .memory:
            let v = Fmt.percent(stats.memory.usage)
            return TileContent(value: v, spark: recent(.memory), sparkMax: 1,
                               spoken: "\(v) used, pressure \(stats.memory.pressure.label)")
        case .network:
            let n = stats.network
            guard n.interface != nil else { return TileContent(value: "Offline", detail: "No connection", spoken: "offline") }
            return TileContent(value: "↓ \(Fmt.compactRate(n.download))", spark: recent(.download),
                               spoken: "downloading \(Fmt.rate(n.download)), uploading \(Fmt.rate(n.upload))")
        case .disk:
            guard let volume = stats.volumes.first(where: { $0.path == "/" }) ?? stats.volumes.first else {
                return TileContent(value: "—", spoken: "unavailable")
            }
            return TileContent(value: Fmt.percent(volume.usage), detail: "\(Fmt.bytes(volume.available)) free",
                               spoken: "\(Fmt.percent(volume.usage)) full, \(Fmt.bytes(volume.available)) free")
        case .sensors:
            guard let hottest = stats.sensors.hottest else { return TileContent(value: "—", detail: "No sensors", spoken: "unavailable") }
            let v = String(format: "%.0f°", hottest)
            return TileContent(value: v, spark: recent(.temperature), spoken: "hottest \(v) Celsius")
        case .battery:
            let b = stats.battery
            guard b.present else { return TileContent(value: "AC", detail: "No battery", spoken: "on AC power") }
            let v = Fmt.percent(b.percent)
            let state = b.isCharging ? "Charging" : b.onAC ? "On power" : "On battery"
            return TileContent(value: v, detail: state, spoken: "\(v), \(state.lowercased())")
        case .clock:
            let now = ClockTicker.shared.now
            let v = now.formatted(date: .omitted, time: .shortened)
            return TileContent(value: v, detail: now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                               spoken: v)
        case .weather:
            guard let forecast = WeatherStore.shared.forecast else {
                return TileContent(value: "—", detail: settings.weatherLocation == nil ? "Pick a city" : "Loading…",
                                   spoken: "unavailable")
            }
            let v = String(format: "%.0f°", forecast.temperature)
            return TileContent(value: v, detail: WeatherCode.describe(forecast.code),
                               spoken: "\(v), \(WeatherCode.describe(forecast.code))")
        }
    }
}

/// 1.5-pt line with a soft fill, newest sample on the right.
struct Sparkline: View {
    let values: [Double]
    let color: Color
    var maxValue: Double? = nil

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let peak = max(maxValue ?? (values.max() ?? 1), 1e-9)
            let step = size.width / CGFloat(max(values.count - 1, 1))
            let points = values.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * step, y: size.height - size.height * CGFloat(min(max(v, 0) / peak, 1)) * 0.9 - 1)
            }
            var line = Path()
            line.addLines(points)
            var area = line
            area.addLine(to: CGPoint(x: points.last!.x, y: size.height))
            area.addLine(to: CGPoint(x: points[0].x, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.28), color.opacity(0)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
