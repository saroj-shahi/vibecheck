import SwiftUI

/// Row of three quick toggles on the deck home: dark mode, microphone mute, Empty Trash.
struct QuickTogglesView: View {
    private let actions = QuickActions.shared
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if confirming {
                confirmRow
            } else {
                HStack(spacing: 8) {
                    chip(symbol: actions.isDark ? "moon.fill" : "sun.max", label: "Dark", on: actions.isDark,
                         spoken: "Dark mode, \(actions.isDark ? "on" : "off")",
                         help: "Switch to \(actions.isDark ? "light" : "dark") mode") { actions.toggleDarkMode() }
                    chip(symbol: actions.isMicMuted ? "mic.slash.fill" : "mic.fill", label: "Mic", on: actions.isMicMuted,
                         spoken: "Microphone, \(actions.isMicMuted ? "muted" : "on")",
                         help: actions.isMicMuted ? "Unmute the microphone" : "Mute the microphone") { actions.toggleMic() }
                    chip(symbol: "trash", label: QuickActionsText.trashLabel(count: actions.trashCount), on: false,
                         spoken: QuickActionsText.trashSpoken(count: actions.trashCount), help: "Empty Trash",
                         disabled: actions.trashCount == 0) {
                        withAnimation(Deck.animation) { confirming = true }
                    }
                }
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

    private var confirmRow: some View {
        HStack(spacing: 8) {
            Text(QuickActionsText.confirmPrompt(count: actions.trashCount))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
            Button("Cancel") { withAnimation(Deck.animation) { confirming = false } }
                .buttonStyle(QuickChipStyle(on: false))
            Button("Empty") {
                withAnimation(Deck.animation) { confirming = false }
                actions.emptyTrash()
            }
            .buttonStyle(QuickChipStyle(on: true))
            .accessibilityLabel(QuickActionsText.trashSpoken(count: actions.trashCount))
        }
    }

    private func chip(symbol: String, label: String, on: Bool, spoken: String, help: String,
                      disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(QuickChipStyle(on: on))
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(spoken)
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
