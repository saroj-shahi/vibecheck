import AppKit
import SwiftUI

/// Health ring: full when vibing, two-thirds when mid, one-third when cooked. In the menu bar it stays
/// monochrome while vibing and only takes a color when something's wrong.
struct VibeRing: View {
    let vibe: Vibe
    var size: CGFloat = 16
    var lineWidth: CGFloat = 2.25
    /// nil: follow Settings (monochrome unless "Always color the ring" is on).
    var monochromeWhenVibing: Bool?
    /// A keep-awake session runs: a small cup sits in the ring's centre.
    var awake = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var checkTrigger = 0

    var body: some View {
        let mono = monochromeWhenVibing ?? !AppSettings.shared.menuBar.alwaysColorRing
        let color: Color = vibe == .vibing && mono ? .primary : vibe.color
        let ring = shape(color: color)
            .frame(width: size, height: size)
        .overlay {
            if awake {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Menu bar only (the deck passes an explicit color mode).
            if monochromeWhenVibing == nil, AppSettings.shared.menuBar.pulseOnNeedsInput, VibeHooks.shared.needsInput {
                HookPulseDot(size: size, reduceMotion: reduceMotion)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            RecoveryCheckOverlay(trigger: checkTrigger, lineWidth: lineWidth, reduceMotion: reduceMotion)
                .padding(lineWidth + size * 0.12)
        }
        .onChange(of: vibe) { old, new in
            if RecoveryCheck.isRecovery(from: old, to: new) { checkTrigger += 1 }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.75),
                   value: vibe)
        .accessibilityElement()
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(awake ? "Vibe: \(vibe.title). Keeping your Mac awake." : "Vibe: \(vibe.title)")

        if reduceMotion {
            ring
        } else {
            // One small bounce when the state changes.
            ring.keyframeAnimator(initialValue: 1.0, trigger: vibe) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.18, duration: 0.16)
                SpringKeyframe(1.0, duration: 0.3)
            }
        }
    }

    /// The custom SF Symbol (`vibe.ring.<state>`, from `scripts/render_ring_symbol.swift`) when the app's asset
    /// catalog is there; drawn shapes otherwise (tests, `swift run`). The symbol renders as a glyph, so state
    /// changes swap it with a symbol replace instead of animating a trimmed stroke.
    @ViewBuilder
    private func shape(color: Color) -> some View {
        if RingWobble.isWobbling(vibe), !reduceMotion {
            // Bad news moves: a few bumps roll around the ring while mid or cooked.
            WobbleRing(vibe: vibe, color: color, lineWidth: lineWidth)
        } else if RingSymbol.isAvailable {
            Image(RingSymbol.name(vibe))
                .symbolRenderingMode(.palette)
                .foregroundStyle(color, .primary.opacity(0.22))
                .font(.system(size: size / RingSymbol.outerDiameter, weight: RingSymbol.weight(lineWidth: lineWidth, size: size)))
                .contentTransition(.symbolEffect(.replace))
        } else {
            ZStack {
                Circle().stroke(.primary.opacity(0.22), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: vibe.ringFill)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(lineWidth / 2)
        }
    }
}

/// An orange dot at the ring's corner that breathes (opacity and scale, 1.6 s) while an agent needs you.
/// Reduce Motion: the same dot, still. The timer exists only while this view is in a window, and stops
/// with the tick (display asleep, screen locked); the dot is only in the tree while a hook needs input.
private struct HookPulseDot: NSViewRepresentable {
    let size: CGFloat
    let reduceMotion: Bool

    func makeNSView(context: Context) -> HookPulseView { HookPulseView(reduceMotion: reduceMotion) }
    func updateNSView(_ view: HookPulseView, context: Context) { view.reduceMotion = reduceMotion }
    static func dismantleNSView(_ view: HookPulseView, coordinator: ()) { view.stop() }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HookPulseView, context: Context) -> CGSize? {
        CGSize(width: size * 0.42, height: size * 0.42)
    }
}

final class HookPulseView: NSView {
    static let period = 1.6
    private let dot = CALayer()
    private var timer: Timer?
    private var started = Date()
    nonisolated(unsafe) private var gateObserver: NSObjectProtocol?
    var reduceMotion: Bool { didSet { if reduceMotion { stop(); render(phase: 0) } else { startIfNeeded() } } }

    init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true
        dot.backgroundColor = NSColor.systemOrange.cgColor
        dot.actions = ["opacity": NSNull(), "transform": NSNull(), "bounds": NSNull(), "position": NSNull(), "cornerRadius": NSNull()]
        layer?.addSublayer(dot)
        setAccessibilityElement(false)
        render(phase: 0)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        dot.bounds = CGRect(origin: .zero, size: bounds.size)
        dot.position = CGPoint(x: bounds.midX, y: bounds.midY)
        dot.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stop()
            if let gateObserver { NotificationCenter.default.removeObserver(gateObserver) }
            gateObserver = nil
        } else { startIfNeeded() }
    }

    deinit {
        if let gateObserver { NotificationCenter.default.removeObserver(gateObserver) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func startIfNeeded() {
        if gateObserver == nil {
            gateObserver = NotificationCenter.default.addObserver(forName: .vibeCheckTickSuspendedChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if TickGate.isSuspended { self.stop() } else { self.startIfNeeded() }
                }
            }
        }
        guard timer == nil, window != nil, !reduceMotion, !TickGate.isSuspended else { return }
        started = Date()
        let timer = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.render(phase: Date().timeIntervalSince(self.started) / Self.period)
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// A smooth breathe: 0 at the start, 1 at the half period.
    private func render(phase: Double) {
        let breathe = reduceMotion ? 1 : 0.5 - 0.5 * cos(2 * Double.pi * phase)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.opacity = Float(0.55 + 0.45 * breathe)
        dot.transform = CATransform3DMakeScale(0.8 + 0.3 * breathe, 0.8 + 0.3 * breathe, 1)
        CATransaction.commit()
    }
}

/// The "Mood" wobble (chosen on the design canvas): still while vibing, three slow bumps rolling round the
/// ring when mid, four fast ones when cooked. Offsets are fractions of the ring's centre-line radius.
enum RingWobble {
    nonisolated static func isWobbling(_ vibe: Vibe) -> Bool { vibe != .vibing }

    /// Seconds until the pattern repeats (the bumps travel 2π in phase); 0 while still.
    nonisolated static func period(_ vibe: Vibe) -> Double {
        let speed = nodes(vibe).speed
        return speed > 0 ? 2 * Double.pi / speed : 0
    }


    /// Bumps around the ring, their size (fraction of the radius) and how fast they travel (radians / s).
    nonisolated static func nodes(_ vibe: Vibe) -> (count: Double, size: Double, speed: Double) {
        switch vibe {
        case .vibing: (0, 0, 0)
        case .mid: (3, 0.105, 2.6)
        case .cooked: (4, 0.145, 6.5)
        }
    }

    /// Radius offset at `theta` (clockwise from 12 o'clock) at time `t` seconds.
    nonisolated static func offset(theta: Double, t: Double, vibe: Vibe) -> Double {
        let n = nodes(vibe)
        return n.size * sin(n.count * theta - n.speed * t)
    }

    /// The ring from 12 o'clock clockwise over `fraction` of the turn, as a polyline on the wobbling radius.
    nonisolated static func path(center: CGPoint, radius: CGFloat, fraction: Double, t: Double, vibe: Vibe) -> Path {
        let end = 2 * Double.pi * min(max(fraction, 0), 1)
        let steps = max(12, Int((96 * fraction).rounded(.up)))
        var path = Path()
        for i in 0...steps {
            let theta = end * Double(i) / Double(steps)
            let r = Double(radius) * (1 + offset(theta: theta, t: t, vibe: vibe))
            let point = CGPoint(x: center.x + r * sin(theta), y: center.y - r * cos(theta))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        if fraction >= 1 { path.closeSubpath() }
        return path
    }
}

/// The wobbling ring (mid / cooked). One period of shapes is built once; a light timer (20 fps) then swaps
/// the shape layers' paths. Only this view's own layers change, never SwiftUI's layout (a SwiftUI
/// TimelineView at 30 fps cost about 27% CPU in the menu bar), and a repeating Core Animation keyframe
/// animation didn't play in the status bar. Same size and stroke as the static ring; the bumps may poke a
/// fraction of a point past its frame. The timer runs only while the view is in a window.
private struct WobbleRing: NSViewRepresentable {
    let vibe: Vibe
    let color: Color
    let lineWidth: CGFloat

    func makeNSView(context: Context) -> WobbleRingView { WobbleRingView() }

    func updateNSView(_ view: WobbleRingView, context: Context) {
        view.configure(vibe: vibe, color: NSColor(color), lineWidth: lineWidth)
    }

    static func dismantleNSView(_ view: WobbleRingView, coordinator: ()) { view.stop() }
}

final class WobbleRingView: NSView {
    static let framesPerSecond = 20.0
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()
    private var vibe: Vibe?
    private var color = NSColor.systemYellow
    private var lineWidth: CGFloat = 2.25
    private var builtFor: (Vibe, CGSize, CGFloat)?
    private var frames: [(track: CGPath, arc: CGPath)] = []
    private var frameIndex = 0
    private var timer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Layer-hosting (layer set before wantsLayer): AppKit leaves this layer tree to us.
        layer = CALayer()
        wantsLayer = true
        for shape in [track, arc] {
            shape.fillColor = nil
            shape.lineCap = .round
            shape.lineJoin = .round
            shape.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer?.addSublayer(shape)
        }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(vibe: Vibe, color: NSColor, lineWidth: CGFloat) {
        self.vibe = vibe
        self.color = color
        self.lineWidth = lineWidth
        applyColors()
        rebuildIfNeeded()
    }

    override func layout() {
        super.layout()
        rebuildIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() } else { startIfNeeded() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @ObservationIgnored private var gateObserver: NSObjectProtocol?

    /// Follows the tick: nobody is looking while the display sleeps or the Mac is locked.
    private func observeGate() {
        guard gateObserver == nil else { return }
        gateObserver = NotificationCenter.default.addObserver(forName: .vibeCheckTickSuspendedChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if TickGate.isSuspended { self.stop() } else { self.startIfNeeded() }
            }
        }
    }

    private func startIfNeeded() {
        observeGate()
        guard timer == nil, window != nil, frames.count > 1, !TickGate.isSuspended else { return }
        let timer = Timer(timeInterval: 1 / Self.framesPerSecond, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func advance() {
        guard !frames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % frames.count
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.path = frames[frameIndex].track
        arc.path = frames[frameIndex].arc
        CATransaction.commit()
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            track.strokeColor = NSColor.labelColor.withAlphaComponent(0.22).cgColor
            arc.strokeColor = color.cgColor
        }
    }

    /// Rebuilds one period of frames only when the state, size or stroke changes, never per tick.
    private func rebuildIfNeeded() {
        guard let vibe, bounds.width > 0, bounds.height > 0 else { return }
        if let built = builtFor, built.0 == vibe, built.1 == bounds.size, built.2 == lineWidth { return }
        builtFor = (vibe, bounds.size, lineWidth)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = (min(bounds.width, bounds.height) - lineWidth) / 2
        // RingWobble draws y-down (12 o'clock at the top); the layer is y-up, so flip.
        var flip = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
        let period = RingWobble.period(vibe)
        let count = max(1, Int((period * Self.framesPerSecond).rounded()))
        frames = (0..<count).compactMap { i in
            let t = period * Double(i) / Double(count)
            guard let track = RingWobble.path(center: center, radius: radius, fraction: 1, t: t, vibe: vibe).cgPath.copy(using: &flip),
                  let arc = RingWobble.path(center: center, radius: radius, fraction: vibe.ringFill, t: t, vibe: vibe).cgPath.copy(using: &flip)
            else { return nil }
            return (track, arc)
        }
        frameIndex = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in [track, arc] {
            shape.frame = bounds
            shape.lineWidth = lineWidth
        }
        track.path = frames.first?.track
        arc.path = frames.first?.arc
        CATransaction.commit()
        startIfNeeded()
    }
}

/// The vibe ring as custom SF Symbols, one per state, compiled into the app's Assets.car by build.sh.
enum RingSymbol {
    /// Assets.car only exists in the built app (build.sh runs actool), never in `swift test` / `swift run`.
    static let isAvailable = Bundle.main.url(forResource: "Assets", withExtension: "car") != nil
            && NSImage(named: name(.vibing)) != nil

    /// Outer diameter of the regular-weight ring as a fraction of the point size (93 / 100 in the template).
    static let outerDiameter: CGFloat = 0.93

    nonisolated static func name(_ vibe: Vibe) -> String {
        switch vibe {
        case .vibing: "vibe.ring.vibing"
        case .mid: "vibe.ring.mid"
        case .cooked: "vibe.ring.cooked"
        }
    }

    /// Regular matches the menu bar's 2.25 / 16 stroke; thinner rings (the deck's 3.5 / 30) use light.
    nonisolated static func weight(lineWidth: CGFloat, size: CGFloat) -> Font.Weight {
        lineWidth / size < 0.13 ? .light : .regular
    }
}

/// Status item content for the standalone vibe item (used with separate menu bar items).
struct VibeItemLabel: View {
    @Environment(SystemStats.self) private var stats
    @Environment(AppSettings.self) private var settings
    /// Only the real menu bar item has one (Settings' preview draws this label too), so it's optional.
    @Environment(RingDropState.self) private var drop: RingDropState?

    /// The ring earns width only with bad news: "CPU 96%" beside it while mid or cooked, unless the culprit's
    /// own item is already in the menu bar (it would say the same thing twice).
    nonisolated static func shownBadge(_ report: VibeReport, ringShown: Bool, isShown: (Module) -> Bool) -> String? {
        guard ringShown, let badge = report.badge else { return nil }
        if let culprit = report.culprit, isShown(culprit) { return nil }
        return badge
    }

    var body: some View {
        HStack(spacing: settings.menuBar.spacing.between) {
            if settings.menuBar.ringVisible {
                HStack(spacing: 4) {
                    VibeRing(vibe: stats.vibe.vibe, awake: AwakeCup.inRing(settings))
                        .scaleEffect(drop?.isTargeted == true ? RingDropState.scale : 1)
                        .animation(.easeOut(duration: 0.12), value: drop?.isTargeted == true)
                    if let badge = Self.shownBadge(stats.vibe, ringShown: true, isShown: settings.showsInMenuBar) {
                        Text(badge).font(.system(size: 11, weight: .medium).monospacedDigit()).lineLimit(1)
                    }
                }
                .frame(height: 22)
            }
            if AwakeCup.isShown(settings) { AwakeCup() }
        }
            .padding(.horizontal, max(settings.menuBar.spacing.padding, 2))
    }
}
