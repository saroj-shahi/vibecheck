import SwiftUI

/// Health ring: full when vibing, two-thirds when mid, one-third when cooked. In the menu bar it stays
/// monochrome while vibing and only takes a color when something's wrong.
struct VibeRing: View {
    let vibe: Vibe
    var size: CGFloat = 16
    var lineWidth: CGFloat = 2.25
    var monochromeWhenVibing = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color: Color = vibe == .vibing && monochromeWhenVibing ? .primary : vibe.color
        let ring = ZStack {
            Circle().stroke(.primary.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: vibe.ringFill)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.75),
                   value: vibe)
        .accessibilityElement()
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel("Vibe: \(vibe.title)")

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
}

/// Status item content for the standalone vibe item (used with separate menu bar items).
struct VibeItemLabel: View {
    @Environment(SystemStats.self) private var stats
    @Environment(AppSettings.self) private var settings

    /// The ring earns width only with bad news: "CPU 96%" beside it while mid or cooked, unless the culprit's
    /// own item is already in the menu bar (it would say the same thing twice).
    static func shownBadge(_ report: VibeReport, ringShown: Bool, isShown: (Module) -> Bool) -> String? {
        guard ringShown, let badge = report.badge else { return nil }
        if let culprit = report.culprit, isShown(culprit) { return nil }
        return badge
    }

    var body: some View {
        HStack(spacing: settings.menuBarSpacing.between) {
            if settings.showVibeRing {
                HStack(spacing: 4) {
                    VibeRing(vibe: stats.vibe.vibe)
                    if let badge = Self.shownBadge(stats.vibe, ringShown: true, isShown: settings.isEnabled) {
                        Text(badge).font(.system(size: 11, weight: .medium).monospacedDigit()).lineLimit(1)
                    }
                }
                .frame(height: 22)
            }
            if AwakeCup.isShown(settings) { AwakeCup() }
        }
            .padding(.horizontal, max(settings.menuBarSpacing.padding, 2))
            .help(stats.vibe.verdict)
    }
}
