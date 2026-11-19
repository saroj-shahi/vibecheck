import SwiftUI

/// Row with one quick toggle on the deck home: microphone mute, filling the row. (Empty Trash lives in
/// the ⌘K palette only.) A toggle that fails shakes; its symbol swaps with a replace transition.
struct QuickTogglesView: View {
    private let actions = QuickActions.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                QuickChip(symbol: actions.isMicMuted ? "mic.slash.fill" : "mic.fill", label: "Mic", on: actions.isMicMuted,
                          spoken: actions.isMicMuted ? String(localized: "Microphone, muted") : String(localized: "Microphone, on"),
                          help: actions.isMicMuted ? "Unmute the microphone" : "Mute the microphone",
                          failTick: actions.failedToggle == .mic ? actions.failureTick : 0) { actions.toggleMic() }
            }
            if let message = actions.failure {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(Deck.animation, value: actions.failure)
        .onAppear { actions.refresh() }
    }
}

/// Horizontal shake: `amount` pt side to side, two swings per whole step of `progress`.
struct ShakeEffect: GeometryEffect {
    static let amount: CGFloat = 3
    static let duration = 0.24
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: Self.amount * sin(progress * .pi * 4), y: 0))
    }
}

private struct QuickChip: View {
    let symbol: String
    let label: LocalizedStringKey
    let on: Bool
    let spoken: String
    let help: LocalizedStringKey
    /// Changes whenever this toggle's action fails; 0 while it is not the one that failed.
    let failTick: Int
    let action: () -> Void
    @State private var shake: CGFloat = 0
    @State private var dimmed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .animation(Deck.reduceMotion ? nil : .default, value: symbol)
                Text(label).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(QuickChipStyle(on: on))
        .modifier(ShakeEffect(progress: shake))
        .opacity(dimmed ? 0.35 : 1)
        .help(help)
        .accessibilityLabel(spoken)
        .onChange(of: failTick) { _, tick in
            guard tick != 0 else { return }
            if Deck.reduceMotion {
                // No motion: fade down and back up instead.
                withAnimation(.easeOut(duration: ShakeEffect.duration / 2)) { dimmed = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(120))
                    withAnimation(.easeIn(duration: ShakeEffect.duration / 2)) { dimmed = false }
                }
            } else {
                shake = 0
                withAnimation(.linear(duration: ShakeEffect.duration)) { shake = 1 }
            }
        }
    }
}

/// Quiet chip matching the tile fill; tinted when the toggle is on.
private struct QuickChipStyle: ButtonStyle {
    let on: Bool
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .frame(height: 30)
            .foregroundStyle(on ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(on ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                             : AnyShapeStyle(.quaternary.opacity(hovering ? 0.9 : 0.55)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !Deck.reduceMotion ? 0.97 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }
}
