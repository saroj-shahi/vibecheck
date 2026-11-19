import SwiftUI

/// Health ring: full when vibing, two-thirds when mid, one-third when cooked. In the menu bar it stays
/// monochrome while vibing and only takes a color when something's wrong.
struct VibeRing: View {
    let vibe: Vibe
    var size: CGFloat = 16
    var lineWidth: CGFloat = 2.25
    var monochromeWhenVibing = true
    /// A keep-awake session runs: a small cup sits in the ring's centre.
    var awake = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var checkTrigger = 0

    var body: some View {
        let color: Color = vibe == .vibing && monochromeWhenVibing ? .primary : vibe.color
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
        if RingSymbol.isAvailable {
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
