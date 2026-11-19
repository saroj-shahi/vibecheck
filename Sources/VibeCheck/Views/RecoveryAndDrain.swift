import SwiftUI

/// Pure transition rules for the ring's one-off animations.
enum RecoveryCheck {
    /// The check draws only when the vibe climbs back to vibing from mid or cooked. Launch never counts:
    /// there is no previous reading, and `onChange` does not fire for the first one.
    nonisolated static func isRecovery(from old: Vibe?, to new: Vibe) -> Bool {
        guard let old, new == .vibing else { return false }
        return old == .mid || old == .cooked
    }
}

/// The brand's pulse-to-check path (branding/svg/mark-mono.svg, viewBox 196...828) fitted to a rect.
struct PulseCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [(300, 532), (392, 532), (440, 452), (506, 640), (772, 328)]
        func p(_ t: (CGFloat, CGFloat)) -> CGPoint {
            CGPoint(x: rect.minX + (t.0 - 196) / 632 * rect.width, y: rect.minY + (t.1 - 196) / 632 * rect.height)
        }
        var path = Path()
        path.move(to: p(pts[0]))
        for t in pts.dropFirst() { path.addLine(to: p(t)) }
        return path
    }
}

/// Draws the mark across the ring once each time `trigger` increments, then fades out.
struct RecoveryCheckOverlay: View {
    let trigger: Int
    let lineWidth: CGFloat
    let reduceMotion: Bool
    @State private var trim: CGFloat = 0
    @State private var opacity: Double = 0

    var body: some View {
        PulseCheckShape()
            .trim(from: 0, to: reduceMotion ? 1 : trim)
            .stroke(.primary, style: StrokeStyle(lineWidth: max(lineWidth * 0.8, 1.2), lineCap: .round, lineJoin: .round))
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: trigger) { _, _ in play() }
    }

    private func play() {
        trim = 0
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.15)) { opacity = 1 }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(.easeInOut(duration: 0.15)) { opacity = 0 }
            }
            return
        }
        opacity = 1
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { trim = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(.easeOut(duration: 0.3)) { opacity = 0 }
        }
    }
}

/// Set when the user quits a process from the deck while a culprit is flagged: the culprit outline drains
/// and the number rolls down without waiting for the next sample. Cleared once the verdict catches up.
@MainActor @Observable
final class CulpritDrain {
    static let shared = CulpritDrain()
    private(set) var active = false

    func start(culpritPresent: Bool) {
        guard culpritPresent else { return }
        withAnimation(.easeIn(duration: 0.4)) { active = true }
    }

    func clear() { if active { active = false } }
}
