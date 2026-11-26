import SwiftUI

extension EnvironmentValues {
    /// Shared namespace so tiles and detail headers can morph into each other.
    @Entry var deckNamespace: Namespace.ID? = nil
    /// True inside the deck's detail view; shows a back chevron in the panel header.
    @Entry var deckShowsBack = false
}

struct DeckHeightKey: PreferenceKey {
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
    var onWidth: () -> Void = {}
    var onDragResize: (CGFloat, Bool) -> Void = { _, _ in }
    var onResetHeight: () -> Void = {}
    @Environment(DeckModel.self) private var model
    @Environment(SystemStats.self) private var stats
    @Environment(AppSettings.self) private var settings
    @Namespace private var namespace
    @State private var contentHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0

    var body: some View {
        let detail: Module? = if case .module(let module) = model.route, !model.paletteOpen { module } else { nil }
        let activeWidth = Deck.width(for: model.route, paletteOpen: model.paletteOpen)
        let isResizableClock = detail == .clock
        VStack(spacing: 0) {
            // A detail view's header row stays put while its content scrolls.
            if let detail {
                PanelHeader(module: detail, showsBack: true)
                    .padding([.horizontal, .top], 16)
                    .padding(.bottom, 12)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                    .transition(.opacity)
            }
            if detail == .clock {
                // Date & Time manages its own internal scroll so the month calendar stays pinned sticky
                // while only the events list scrolls.
                ClockPanel()
                    .environment(\.deckShowsBack, true)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            } else {
                ScrollView(.vertical) {
                    Group {
                        if let detail {
                            ModulePanel(module: detail)
                                .environment(\.deckShowsBack, true)
                                .transition(.opacity)
                        } else {
                            DeckShell()
                                .transition(.opacity)
                        }
                    }
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: DeckHeightKey.self, value: proxy.size.height)
                    })
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.automatic)
            }

            if isResizableClock {
                DeckResizeHandle(onDrag: onDragResize, onDoubleClick: onResetHeight)
            }
        }
        .environment(\.deckNamespace, namespace)
        .onAppear { DeckCommands.stats = stats }
        .frame(width: activeWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(DeckHeightKey.self) { height in
            MainActor.assumeIsolated { contentHeight = height }
        }
        .onChange(of: contentHeight + (detail == nil ? 0 : headerHeight) + (isResizableClock ? DeckResizeHandle.height : 0), initial: true) { _, total in
            onHeight(total)
        }
        .onChange(of: activeWidth) { _, _ in onWidth() }
        .background {
            if settings.deckOpacity > 0 {
                RoundedRectangle(cornerRadius: Deck.cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(settings.deckOpacity))
                    .allowsHitTesting(false)
            }
        }
        .overlay { GlassHairline() }
    }
}

/// Bottom mouse-drag resize grip for the Date & Time popover. Uses screen-space `NSEvent.mouseLocation`
/// so live window resizing never suffers SwiftUI local coordinate feedback jitter. Double-click resets to auto height.
private struct DeckResizeHandle: View {
    static let height: CGFloat = 14
    let onDrag: (CGFloat, Bool) -> Void
    let onDoubleClick: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(.primary.opacity(hovering ? 0.36 : 0.16))
                .frame(width: 36, height: 3.5)
            ResizeDragNSView(onHover: { hovering = $0 }, onDrag: onDrag, onDoubleClick: onDoubleClick)
        }
        .frame(height: Self.height)
        .help("Drag to resize height · double-click to reset")
        .accessibilityLabel("Resize Date & Time panel height")
    }
}

private struct ResizeDragNSView: NSViewRepresentable {
    let onHover: (Bool) -> Void
    let onDrag: (CGFloat, Bool) -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> ResizeGripView {
        let view = ResizeGripView()
        view.onHover = onHover
        view.onDrag = onDrag
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: ResizeGripView, context: Context) {
        nsView.onHover = onHover
        nsView.onDrag = onDrag
        nsView.onDoubleClick = onDoubleClick
    }
}

private final class ResizeGripView: NSView {
    var onHover: ((Bool) -> Void)?
    var onDrag: ((CGFloat, Bool) -> Void)?
    var onDoubleClick: (() -> Void)?
    private var startScreenY: CGFloat?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeUpDown.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeUpDown.set()
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        if startScreenY == nil { NSCursor.arrow.set() }
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            startScreenY = nil
            onDoubleClick?()
            return
        }
        startScreenY = NSEvent.mouseLocation.y
        NSCursor.resizeUpDown.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startScreenY else { return }
        // Screen Y increases upward, so dragging downward (negative screen delta) grows the panel height.
        let delta = startScreenY - NSEvent.mouseLocation.y
        onDrag?(delta, false)
    }

    override func mouseUp(with event: NSEvent) {
        guard let startScreenY else { return }
        let delta = startScreenY - NSEvent.mouseLocation.y
        self.startScreenY = nil
        onDrag?(delta, true)
        NSCursor.arrow.set()
    }
}

/// Inner edge so the pre-Liquid Glass blur reads as a sheet of glass (white 10% dark, black 8% light).
/// 0.5 pt on Retina; on a 1× display that would smear, so it's 1 px at half the opacity there.
/// Liquid Glass (macOS 26) draws its own edge, so nothing is added there.
private struct GlassHairline: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        // The opaque Reduce Transparency background has no glass edge of its own, on any macOS.
        if reduceTransparency || { if #available(macOS 26, *) { false } else { true } }() {
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
        .overlay(alignment: .topTrailing) {
            if model.awakeDialOpen {
                AwakeDialView(selection: model.awakeDialSelection)
                    .padding(.top, 6)
                    .padding(.trailing, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .topTrailing)))
            }
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
        .accessibilityHint(open ? String(localized: "Type to filter; Escape clears") : String(localized: "Opens the action search"))
    }
}

/// One pill per thing happening right now. The row doesn't exist when nothing is live.
private struct LiveChipsRow: View {
    let secureInput: SecureInputStatus?

    var body: some View {
        let session = KeepAwake.shared.session
        let micMuted = QuickActions.shared.isMicMuted
        let hooks = VibeHooks.shared.hooks
        if session != nil || micMuted || secureInput != nil || !hooks.isEmpty {
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
                             help: LocalizedStringKey(secureInput.message)) {
                        (NSApp.delegate as? AppDelegate)?.showSettings(.shortcuts)
                    }
                }
                ForEach(hooks.prefix(3)) { HookPill(hook: $0) }
                if hooks.count > 3 {
                    Text("+\(hooks.count - 3)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .frame(height: 28)
                        .background(Capsule().fill(.quaternary.opacity(0.55)))
                        .help("\(hooks.count - 3) more from ~/.config/vibecheck/hooks")
                }
                Spacer(minLength: 0)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

/// A pill for a hook file written by another tool. No ×: VibeCheck doesn't own it.
private struct HookPill: View {
    let hook: VibeHook

    var body: some View {
        let tint: Color = switch hook.state {
        case .needsInput: .orange
        case .error: .red
        default: .secondary
        }
        HStack(spacing: 5) {
            if let icon = hook.icon {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            } else {
                Circle().fill(tint).frame(width: 7, height: 7)
            }
            Text(hook.label).font(.system(size: 12, weight: .medium)).lineLimit(1)
            if !hook.value.isEmpty {
                Text(hook.value).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Capsule().fill(.quaternary.opacity(0.55)))
        .overlay(Capsule().strokeBorder(tint.opacity(hook.state == .needsInput || hook.state == .error ? 0.6 : 0), lineWidth: 1))
        .help("From \(hook.file), updated \(hook.updatedAt.formatted(.relative(presentation: .named)))")
        .accessibilityElement(children: .combine)
    }
}

/// A live pill. With `stopLabel` it shows a × on hover that runs `action`; without, the whole pill is the button.
private struct LiveChip: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    var detail: String? = nil
    var help: LocalizedStringKey? = nil
    var stopLabel: LocalizedStringKey? = nil
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
            if let notice = model.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                Spacer(minLength: 0)
            } else if let query = model.paletteQuery {
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
                FooterButton(symbol: "heart", title: "Support", help: "Support VibeCheck: Buy Me a Coffee") {
                    NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/sarojshahi")!)
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
    let title: LocalizedStringKey?
    let help: LocalizedStringKey
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

/// Quick toggles and the bento grid. Tiles are 108 pt: (372 − 2 × 16 − 2 × 8) / 3, whole pixels at 1× and 2×.
struct DeckHome: View {
    @Environment(DeckModel.self) private var model
    @AppStorage("showQuickToggles") private var showQuickToggles = true
    @AppStorage("showDeckSummary") private var showDeckSummary = true

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Deck.gutter), count: Deck.columns)

    var body: some View {
        // One hint line at a time: the overnight note first; the what's-new tip shows once it's dismissed.
        if let report = SleepDrain.shared.report {
            SleepDrainLineView(report: report)
        } else {
            DeckHintView()
        }
        ExplainCardView()
        if showQuickToggles {
            QuickTogglesView()
        }
        if showDeckSummary {
            DeckSummaryCard()
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
    let help: LocalizedStringKey
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
    private var drain: CulpritDrain { .shared }

    var body: some View {
        let content = TileContent.make(module, stats: stats, settings: settings)
        // The tile behind a mid / cooked verdict: the verdict says why, the outline says where.
        // Right after the user quits the culprit, the outline drains without waiting for the next sample.
        let culprit: Vibe? = stats.vibe.culprit == module && !drain.active ? stats.vibe.vibe : nil
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
                    .animation(Deck.reduceMotion ? nil : .easeOut(duration: 0.4), value: content.value)
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
                // A second fact under the chart (top app, memory in GB, time left…), so a glance says more
                // than one number. Always takes its line, so the grid's rows stay the same height.
                Text(content.note ?? " ")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .contentTransition(.opacity)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 90, maxHeight: 90, alignment: .topLeading)
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
        .onChange(of: stats.vibe.culprit) { _, _ in drain.clear() }
        .onChange(of: stats.vibe.vibe) { _, _ in drain.clear() }
        .onHover { hovering in withAnimation(.easeOut(duration: hovering ? 0.15 : 0.12)) { self.hovering = hovering } }
        .accessibilityLabel((culprit.map { String(localized: "\(module.title), \(content.spoken), making your Mac \($0.title.lowercased())") }
                             ?? String(localized: "\(module.title), \(content.spoken)")) + (content.note.map { ", \($0)" } ?? ""))
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
    /// The tile's bottom line; nil leaves it blank.
    var note: String?

    @MainActor
    static func make(_ module: Module, stats: SystemStats, settings: AppSettings) -> TileContent {
        var content = base(module, stats: stats, settings: settings)
        if content.note == nil { content.note = note(module, stats: stats) }
        return content
    }

    /// Second facts per module, from readings the tick already has (nothing extra is sampled for them).
    /// The deck home samples processes every 5 s for the verdict, so the top app is there while it's open.
    @MainActor
    static func note(_ module: Module, stats: SystemStats) -> String? {
        switch module {
        case .cpu:
            if let top = stats.topApps(by: \.cpu, limit: 1).first, top.cpu >= 1 {
                return appNote(top.name, cpuText(top.cpu))
            }
            return String(localized: "User \(Fmt.percent(stats.cpu.user)) · Sys \(Fmt.percent(stats.cpu.system))")
        case .gpu:
            // No per-app GPU readings exist without extra sampling, so the GPU's own memory stays.
            guard let gpu = stats.gpu.gpus.max(by: { $0.device < $1.device }) else { return nil }
            if let inUse = gpu.memoryInUse, inUse > 0 { return String(localized: "\(Fmt.bytes(inUse)) in use") }
            return gpu.cores.map { String(localized: "\(String($0)) cores") }
        case .memory:
            if let top = stats.topApps(by: \.memory, limit: 1).first, top.memory > 0 {
                return appNote(top.name, Fmt.bytes(top.memory))
            }
            if let top = topMemoryTrack(stats.appMemoryTracks) {
                return appNote(top.name, Fmt.bytes(top.footprint))
            }
            let m = stats.memory
            if m.swapUsed >= 1_073_741_824 { return String(localized: "\(Fmt.bytes(m.used)) · swap \(Fmt.bytes(m.swapUsed))") }
            return String(localized: "\(Fmt.bytes(m.used)) of \(Fmt.bytes(m.total))")
        case .network:
            let n = stats.network
            guard let interface = n.interface else { return nil }
            return networkNote(upload: n.upload, link: n.interfaces.first { $0.bsdName == interface }?.displayName)
        case .disk:
            return nil
        case .sensors:
            return sensorNote(fanRPM: stats.sensors.fans.map(\.rpm).max(), thermal: stats.thermalState,
                              hottestName: stats.sensors.summary.first?.name)
        case .battery:
            let b = stats.battery
            guard b.present, let minutes = b.minutesRemaining, minutes > 0 else { return nil }
            if b.isCharging { return String(localized: "\(Fmt.uptime(TimeInterval(minutes * 60))) to full") }
            return b.onAC ? nil : String(localized: "\(Fmt.uptime(TimeInterval(minutes * 60))) left")
        case .agents:
            // The limit closest to running out, across every agent.
            guard let tightest = DeckFacts.tightestLimit(AgentUsageStore.shared.sample.agents) else { return nil }
            return String(localized: "\(tightest.window.title): \(Fmt.percent(tightest.window.leftPercent / 100)) left")
        case .clock:
            let clockSettings = AppSettings.shared.clock
            let calStore = CalendarStore.shared
            guard clockSettings.showCalendarEvents else { return nil }
            calStore.ensureStarted()
            guard calStore.access == .granted,
                  let next = CalendarLogic.nextEvent(in: calStore.events, now: Date(),
                                                     hiddenCalendarIDs: clockSettings.hiddenCalendarIDs,
                                                     showDuringEntireEvent: true,
                                                     lookaheadMinutes: 480) else { return nil }
            return "\(DeckFacts.shortName(next.title, max: 10)) · \(CalendarLogic.compactCountdown(for: next, now: Date()))"
        case .weather, .todo:
            return nil
        }
    }

    /// "Chrome 46%": the name gives way so the number always shows in a 108-pt tile.
    nonisolated static func appNote(_ name: String, _ amount: String, maxName: Int = 11) -> String {
        "\(DeckFacts.shortName(name, max: maxName)) \(amount)"
    }

    /// Percent of one core, as `ps` and Activity Monitor show it (can pass 100%).
    nonisolated static func cpuText(_ percentOfCore: Double) -> String {
        "\(String(Int(max(0, percentOfCore).rounded())))%"
    }

    /// The app with the largest recent footprint in the once-a-minute memory history (no `ps` needed).
    nonisolated static func topMemoryTrack(_ tracks: [AppMemoryKey: AppMemoryTrack], now: Date = Date())
        -> (name: String, footprint: Double)? {
        tracks.values.compactMap { track in track.samples.last.map { (track.name, $0) } }
            .filter { now.timeIntervalSince($0.1.date) <= AppMemoryHistory.interval * 3 && $0.1.footprint > 0 }
            .max { $0.1.footprint < $1.1.footprint }
            .map { ($0.0, $0.1.footprint) }
    }

    /// "↑ 340K · Wi-Fi"; just the upload when the link has no friendly name.
    nonisolated static func networkNote(upload: Double, link: String?) -> String {
        let up = "↑ \(Fmt.compactRate(upload))"
        guard let link, !link.isEmpty else { return up }
        return "\(up) · \(link)"
    }

    /// Fan speed when a fan spins, else whether macOS is throttling, else the hottest sensor's short name.
    nonisolated static func sensorNote(fanRPM: Double?, thermal: ProcessInfo.ThermalState?, hottestName: String?) -> String? {
        if let fanRPM, fanRPM > 0 { return String(localized: "Fan \(String(format: "%.0f", fanRPM)) rpm") }
        if let thermal {
            switch thermal {
            case .serious, .critical: return String(localized: "Throttling")
            default: return String(localized: "No throttling")
            }
        }
        return hottestName.map(shortSensorName)
    }

    /// "CPU / SoC (hottest)" → "CPU / SoC".
    nonisolated static func shortSensorName(_ name: String) -> String {
        guard let paren = name.firstIndex(of: "(") else { return name }
        let trimmed = name[..<paren].trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : trimmed
    }

    /// "Charging · 28 W" / "On battery · 9.4 W"; the state alone when the draw is unknown or near zero.
    nonisolated static func batteryDetail(state: String, watts: Double?) -> String {
        guard let watts, abs(watts) >= 0.5 else { return state }
        let w = abs(watts)
        return "\(state) · \(w < 10 ? String(format: "%.1f", w) : String(format: "%.0f", w)) W"
    }

    @MainActor
    private static func base(_ module: Module, stats: SystemStats, settings: AppSettings) -> TileContent {
        func recent(_ key: HistoryKey) -> [Double] { Array(stats.live(key).suffix(30)) }
        switch module {
        case .cpu:
            let v = Fmt.percent(stats.cpu.total)
            return TileContent(value: v, spark: recent(.cpu), sparkMax: 1, spoken: String(localized: "\(v) in use"))
        case .gpu:
            guard !stats.gpu.gpus.isEmpty else { return TileContent(value: "—", detail: String(localized: "No GPU stats"), spoken: String(localized: "unavailable")) }
            let v = Fmt.percent(stats.gpu.utilization)
            return TileContent(value: v, spark: recent(.gpu), sparkMax: 1, spoken: String(localized: "\(v) in use"))
        case .memory:
            let v = Fmt.percent(stats.memory.usage)
            return TileContent(value: v, spark: recent(.memory), sparkMax: 1,
                               spoken: String(localized: "\(v) used, pressure \(stats.memory.pressure.label)"))
        case .network:
            let n = stats.network
            guard n.interface != nil else { return TileContent(value: String(localized: "Offline"), detail: String(localized: "No connection"), spoken: String(localized: "offline")) }
            return TileContent(value: "↓ \(Fmt.compactRate(n.download))", spark: recent(.download),
                               spoken: String(localized: "downloading \(Fmt.rate(n.download)), uploading \(Fmt.rate(n.upload))"))
        case .disk:
            guard let volume = stats.volumes.first(where: { $0.path == "/" }) ?? stats.volumes.first else {
                return TileContent(value: "—", spoken: String(localized: "unavailable"))
            }
            return TileContent(value: Fmt.percent(volume.usage), detail: String(localized: "\(Fmt.bytes(volume.available)) free"),
                               spoken: String(localized: "\(Fmt.percent(volume.usage)) full, \(Fmt.bytes(volume.available)) free"))
        case .sensors:
            guard let hottest = stats.sensors.hottest else { return TileContent(value: "—", detail: String(localized: "No sensors"), spoken: String(localized: "unavailable")) }
            let v = String(format: "%.0f°", hottest)
            return TileContent(value: v, spark: recent(.temperature), spoken: String(localized: "hottest \(v) Celsius"))
        case .battery:
            let b = stats.battery
            guard b.present else { return TileContent(value: String(localized: "AC"), detail: String(localized: "No battery"), spoken: String(localized: "on AC power")) }
            let v = Fmt.percent(b.percent)
            let state = b.isCharging ? String(localized: "Charging") : b.onAC ? String(localized: "On power") : String(localized: "On battery")
            return TileContent(value: v, detail: batteryDetail(state: state, watts: b.powerWatts),
                               spoken: String(localized: "\(v), \(state.lowercased())"))
        case .clock:
            let now = ClockTicker.shared.now
            let v = now.formatted(date: .omitted, time: .shortened)
            return TileContent(value: v, detail: now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                               spoken: v)
        case .weather:
            guard let forecast = WeatherStore.shared.forecast else {
                return TileContent(value: "—", detail: settings.weather.location == nil ? String(localized: "Pick a city") : String(localized: "Loading…"),
                                   spoken: String(localized: "unavailable"))
            }
            let v = String(format: "%.0f°", forecast.temperature)
            return TileContent(value: v, detail: WeatherCode.describe(forecast.code),
                               spoken: String(localized: "\(v), \(WeatherCode.describe(forecast.code))"))
        case .agents:
            let sample = AgentUsageStore.shared.sample
            guard sample.scanned else { return TileContent(value: "—", detail: String(localized: "Reading logs…"), spoken: String(localized: "loading")) }
            guard !sample.agents.isEmpty else { return TileContent(value: "—", detail: String(localized: "No agent logs"), spoken: String(localized: "no agent logs found")) }
            let v = Fmt.tokens(sample.today.total)
            return TileContent(value: v, spark: sample.hourly, spoken: String(localized: "\(v) tokens today"))
        case .todo:
            let store = RemindersStore.shared
            store.ensureStarted()   // never prompts; the panel asks when it opens
            switch store.access {
            case .granted where store.loaded:
                let count = store.open.count
                let due = store.dueNowCount
                let detail = count == 0 ? String(localized: "All done")
                    : due > 0 ? String(localized: "\(due) due") : (store.selectedList?.title ?? String(localized: "Open"))
                return TileContent(value: "\(count)", detail: detail,
                                   spoken: due > 0 ? String(localized: "\(count) open, \(due) due") : String(localized: "\(count) open"))
            case .granted:
                return TileContent(value: "—", detail: String(localized: "Loading…"), spoken: String(localized: "loading"))
            case .notAsked:
                return TileContent(value: "—", detail: String(localized: "Connect Reminders"), spoken: String(localized: "not connected to Reminders"))
            default:
                return TileContent(value: "—", detail: String(localized: "No access"), spoken: String(localized: "no access to Reminders"))
            }
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
