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

/// Root of the deck window: the shell (home or palette) or one module's detail, reporting its natural
/// height so the window can resize around it.
struct DeckRoot: View {
    let onHeight: (CGFloat) -> Void
    @Environment(DeckModel.self) private var model
    @Namespace private var namespace

    var body: some View {
        ScrollView(.vertical) {
            Group {
                if case .module(let module) = model.route, !model.paletteOpen {
                    ModulePanel(module: module)
                        .environment(\.deckShowsBack, true)
                        .transition(.opacity)
                } else {
                    DeckShell()
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
        .overlay { GlassHairline() }
    }
}

/// Inner edge so the pre-Liquid Glass blur reads as a sheet of glass (white 10% dark, black 8% light).
/// 0.5 pt on Retina; on a 1× display that would smear, so it's 1 px at half the opacity there.
/// Liquid Glass (macOS 26) draws its own edge, so nothing is added there.
private struct GlassHairline: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var scale

    var body: some View {
        if #unavailable(macOS 26) {
            let retina = scale >= 2
            let opacity = (scheme == .dark ? 0.10 : 0.08) * (retina ? 1 : 0.5)
            RoundedRectangle(cornerRadius: Deck.cornerRadius, style: .continuous)
                .strokeBorder(scheme == .dark ? Color.white.opacity(opacity) : Color.black.opacity(opacity),
                              lineWidth: retina ? 0.5 : 1)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Shell

/// Home and palette share one shell: header, search field, live chips, body, footer.
struct DeckShell: View {
    @Environment(DeckModel.self) private var model
    @Environment(AppSettings.self) private var settings
    /// Set while secure keyboard entry blocks the global shortcuts. A blocked press never reaches
    /// VibeCheck, so the deck says so whenever it's open instead.
    @State private var secureInput: SecureInputStatus?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                DeckHeader()
                DeckSearchField()
                LiveChipsRow(secureInput: secureInput)
                if model.paletteOpen {
                    CommandPaletteView()
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                } else {
                    DeckHome()
                }
            }
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 12)
            DeckFooter()
        }
        .animation(Deck.animation, value: KeepAwake.shared.session)
        .animation(Deck.animation, value: QuickActions.shared.isMicMuted)
        .animation(Deck.animation, value: secureInput)
        .task(id: settings.hotkeysEnabled) {
            // Only while the shell is on screen; cancelled when it goes away.
            while !Task.isCancelled {
                let status = settings.hotkeysEnabled ? SecureInput.current() : nil
                if status != secureInput { secureInput = status }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

/// Ring and verdict, with the only two header buttons that need to be one click away: alerts and the cup.
private struct DeckHeader: View {
    @Environment(SystemStats.self) private var stats

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                VibeRing(vibe: stats.vibe.vibe, size: 30, lineWidth: 3.5, monochromeWhenVibing: false)
                Text(stats.vibe.vibe.title)
                    .font(.system(size: 15, weight: .semibold))
                    .contentTransition(.interpolate)
                Spacer(minLength: 4)
                NotificationBellButton()
                AwakeMenuButton()
            }
            Text(stats.vibe.verdict)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .padding(.leading, 40)
        }
    }
}

/// Always-visible search field. It's drawn, not a text field: the panel never takes focus from the
/// user's app, so typing reaches the palette through the deck's key monitor.
private struct DeckSearchField: View {
    @Environment(DeckModel.self) private var model
    @State private var hovering = false

    var body: some View {
        let query = model.paletteQuery
        let open = query != nil
        Button {
            if !open { model.openPalette() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 1) {
                    if let query, !query.isEmpty {
                        Text(query)
                        Caret(height: 15)
                    } else {
                        if open { Caret(height: 15) }
                        Text("Search or run an action").foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 13))
                .lineLimit(1)
                Spacer(minLength: 4)
                KeyCap(text: open ? "esc" : "⌘K")
            }
            .padding(.leading, 8)
            .padding(.trailing, 5)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(open || hovering ? 0.9 : 0.55)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(open ? 0.55 : 0), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering } }
        .accessibilityLabel(query.map { $0.isEmpty ? "Search actions" : "Search actions, \($0)" } ?? "Search actions (⌘K)")
        .accessibilityHint(open ? "Type to filter; Escape clears" : "Opens the action search")
    }
}

/// One pill per thing happening right now. The row doesn't exist when nothing is live.
private struct LiveChipsRow: View {
    let secureInput: SecureInputStatus?

    var body: some View {
        let session = KeepAwake.shared.session
        let micMuted = QuickActions.shared.isMicMuted
        if session != nil || micMuted || secureInput != nil {
            HStack(spacing: 6) {
                if let session {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        LiveChip(symbol: session.focus ? "timer" : "cup.and.saucer.fill", tint: .accentColor,
                                 title: session.focus ? "Focus" : "Awake",
                                 detail: session.remaining(now: context.date),
                                 stopLabel: session.focus ? "End focus session" : "Stop keeping awake") {
                            KeepAwake.shared.stop()
                        }
                    }
                    .layoutPriority(-1)   // the long one truncates first
                }
                if micMuted {
                    LiveChip(symbol: "mic.slash.fill", tint: .red, title: "Mic muted",
                             stopLabel: "Unmute the microphone") { QuickActions.shared.toggleMic() }
                }
                if let secureInput {
                    LiveChip(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "Shortcuts paused",
                             help: secureInput.message) {
                        (NSApp.delegate as? AppDelegate)?.showSettings(.shortcuts)
                    }
                }
                Spacer(minLength: 0)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

/// A live pill. With `stopLabel` it shows a × on hover that runs `action`; without, the whole pill is the button.
private struct LiveChip: View {
    let symbol: String
    let tint: Color
    let title: String
    var detail: String? = nil
    var help: String? = nil
    var stopLabel: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let stops = stopLabel != nil
        let pill = HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            if let detail {
                Text(detail).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            if let stopLabel {
                Button(action: action) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.quaternary.opacity(0.9)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .help(stopLabel)
                .accessibilityLabel(stopLabel)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, stops ? 4 : 10)
        .frame(height: 26)
        .background(Capsule().fill(tint.opacity(0.13)))
        .contentShape(Capsule())
        .onHover { hovering in withAnimation(.easeOut(duration: hovering ? 0.15 : 0.12)) { self.hovering = hovering } }

        if stops {
            pill.accessibilityElement(children: .contain)
        } else {
            Button(action: action) { pill }
                .buttonStyle(.plain)
                .help(help ?? title)
                .accessibilityLabel(help ?? title)
        }
    }
}

/// Settings, version and Quit; key hints and the result count while the palette is open.
private struct DeckFooter: View {
    @Environment(DeckModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.displayScale) private var scale

    var body: some View {
        HStack(spacing: 10) {
            if let query = model.paletteQuery {
                let count = DeckCommands.filter(DeckCommands.all(model: model, settings: settings), query: query).count
                Group {
                    hint("↩", "run")
                    hint("⌘↩", "actions")
                    hint("esc", query.isEmpty ? "close" : "clear")
                }
                .accessibilityHidden(true)
                Spacer(minLength: 4)
                Text(count == 1 ? "1 result" : "\(count) results")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 6)
            } else {
                FooterButton(symbol: "gearshape", title: "Settings", help: "Settings (⌘,)") {
                    (NSApp.delegate as? AppDelegate)?.showSettings()
                }
                Spacer(minLength: 4)
                Text(Self.versionLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                FooterButton(symbol: "power", title: nil, help: "Quit VibeCheck") { NSApp.terminate(nil) }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .overlay(alignment: .top) {
            Rectangle().fill(.separator).frame(height: 1 / max(scale, 1))
        }
    }

    static var versionLine: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return version.map { "VibeCheck \($0)" } ?? "VibeCheck"
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            KeyCap(text: key)
            Text(label).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
        }
    }
}

private struct FooterButton: View {
    let symbol: String
    let title: String?
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                if let title { Text(title).font(.system(size: 12)) }
            }
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary.opacity(hovering ? 0.9 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? .primary : .secondary)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering } }
    }
}

// MARK: - Home

/// Quick toggles and the bento grid. Tiles are 104 pt: (360 − 2 × 16 − 2 × 8) / 3, whole pixels at 1× and 2×.
struct DeckHome: View {
    @Environment(DeckModel.self) private var model
    @AppStorage("showQuickToggles") private var showQuickToggles = true

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Deck.gutter), count: Deck.columns)

    var body: some View {
        if showQuickToggles {
            QuickTogglesView()
        }
        LazyVGrid(columns: columns, spacing: Deck.gutter) {
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
        // The tile behind a mid / cooked verdict: the verdict says why, the outline says where.
        let culprit: Vibe? = stats.vibe.culprit == module ? stats.vibe.vibe : nil
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: module.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(module.accent)
                        .networkStatusDot(online: stats.network.interface != nil, enabled: module == .network)
                        .deckMatched("icon.\(module.rawValue)", namespace)
                    Text(module.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                // Hover reveal: says "this opens" without a permanent glyph on every tile. An overlay, so the
                // hidden chevron doesn't take width from the title.
                .overlay(alignment: .trailing) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .opacity(hovering ? 0.6 : 0)
                        .offset(x: hovering || Deck.reduceMotion ? 0 : -2)
                        .accessibilityHidden(true)
                }
                Text(content.value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                    .tracking(-0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    // Yellow text is unreadable on light glass, so only cooked tints the number.
                    .foregroundStyle(culprit == .cooked ? Color.red : Color.primary)
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
                    .strokeBorder((culprit?.color ?? .clear).opacity(0.4), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(focused ? 1 : 0)
            )
            .animation(culprit != nil ? .easeOut(duration: 0.24) : .easeIn(duration: 0.4), value: culprit)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(TilePressStyle())
        .onHover { hovering in withAnimation(.easeOut(duration: hovering ? 0.15 : 0.12)) { self.hovering = hovering } }
        .accessibilityLabel("\(module.title), \(content.spoken)" + (culprit.map { ", making your Mac \($0.title.lowercased())" } ?? ""))
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
        case .agents:
            let sample = AgentUsageStore.shared.sample
            guard sample.scanned else { return TileContent(value: "—", detail: "Reading logs…", spoken: "loading") }
            guard !sample.agents.isEmpty else { return TileContent(value: "—", detail: "No agent logs", spoken: "no agent logs found") }
            let v = Fmt.tokens(sample.today.total)
            return TileContent(value: v, spark: sample.hourly, spoken: "\(v) tokens today")
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
