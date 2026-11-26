import SwiftUI

/// Quick controls on the deck home. Row 1: three equal buttons, Mic mute, Bluetooth and Share Vibe Card.
/// Below: volume and brightness sliders, each shown only when this Mac can set it. (Empty Trash lives in
/// the ⌘K palette only.) A toggle that fails shakes; its symbol swaps with a replace transition.
struct QuickTogglesView: View {
    @Environment(DeckModel.self) private var model
    private let actions = QuickActions.shared
    private let volume = SystemVolume.shared
    private let brightness = DisplayBrightness.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                QuickChip(symbol: actions.isMicMuted ? "mic.slash.fill" : "mic.fill", label: "Mic", on: actions.isMicMuted,
                          spoken: actions.isMicMuted ? String(localized: "Microphone, muted") : String(localized: "Microphone, on"),
                          help: actions.isMicMuted ? "Unmute the microphone" : "Mute the microphone",
                          failTick: actions.failedToggle == .mic ? actions.failureTick : 0) { actions.toggleMic() }
                QuickChip(symbol: "dot.radiowaves.left.and.right", label: "Bluetooth", on: actions.bluetoothOn == true, filled: true,
                          spoken: BluetoothTap.spoken(poweredOn: actions.bluetoothOn),
                          help: actions.bluetoothOn == true ? "Turn Bluetooth off" : "Turn Bluetooth on",
                          failTick: actions.failedToggle == .bluetooth ? actions.failureTick : 0) { actions.toggleBluetooth() }
                QuickChip(symbol: "square.and.arrow.up", label: "Share", on: false,
                          spoken: String(localized: "Share Vibe Card"), help: "Share Vibe Card", failTick: 0) {
                    // Same as ⌘K → Share Vibe Card.
                    let stats = DeckCommands.stats
                    model.requestClose?()
                    VibeCardWindow.show(stats: stats)
                }
            }
            if volume.isAvailable {
                LevelRow(value: volume.volume, spokenLabel: String(localized: "Volume"),
                         spokenValue: LevelMath.volumeSpoken(volume: volume.volume, muted: volume.isMuted),
                         dimmed: volume.isMuted,
                         set: { volume.setVolume($0) }, editing: { editing in volume.isEditing = editing; if !editing { volume.refresh() } }) {
                    LevelIcon(symbol: LevelMath.speakerSymbol(volume: volume.volume, muted: volume.isMuted),
                              enabled: volume.canMute,
                              spoken: volume.isMuted ? String(localized: "Unmute") : String(localized: "Mute"),
                              help: volume.isMuted ? "Unmute" : "Mute") { volume.toggleMute() }
                }
            }
            if brightness.isAvailable {
                LevelRow(value: brightness.brightness, spokenLabel: String(localized: "Display brightness"),
                         spokenValue: LevelMath.percentText(brightness.brightness), dimmed: false,
                         set: { brightness.setBrightness($0) }, editing: { brightness.isEditing = $0 }) {
                    LevelIcon(symbol: brightness.brightness < 0.5 ? "sun.min.fill" : "sun.max.fill",
                              enabled: false, spoken: "", help: "Display brightness") {}
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
        .onAppear {
            actions.refresh()
            volume.start()
            brightness.refresh()
        }
        .onDisappear {
            volume.stop()
            brightness.isEditing = false
        }
    }
}

/// Compact slider row: icon, slider, value in a fixed-width slot ("100%" never widens it).
private struct LevelRow<Icon: View>: View {
    let value: Double
    let spokenLabel: String
    let spokenValue: String
    let dimmed: Bool
    let set: (Double) -> Void
    let editing: (Bool) -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: 8) {
            icon()
            Slider(value: Binding(get: { value }, set: { set($0) }), in: 0...1) { isEditing in editing(isEditing) }
                .controlSize(.mini)
                .opacity(dimmed ? 0.5 : 1)
                .accessibilityLabel(spokenLabel)
                .accessibilityValue(spokenValue)
            Text(LevelMath.percentText(value))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.55)))
    }
}

/// The row's leading symbol; a button when `enabled` (the speaker toggles mute).
private struct LevelIcon: View {
    let symbol: String
    let enabled: Bool
    let spoken: String
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        let image = Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .contentTransition(.symbolEffect(.replace))
            .animation(Deck.reduceMotion ? nil : .default, value: symbol)
            .frame(width: 18, height: 18)
        if enabled {
            Button(action: action) { image.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .help(help)
                .accessibilityLabel(spoken)
        } else {
            image.foregroundStyle(.secondary).help(help).accessibilityHidden(true)
        }
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
    /// On draws a solid accent fill with white text (Control Center style) instead of the light tint.
    var filled = false
    let spoken: String
    let help: LocalizedStringKey
    /// Changes whenever this toggle's action fails; 0 while it is not the one that failed.
    let failTick: Int
    let action: () -> Void
    @State private var shake: CGFloat = 0
    @State private var dimmed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .animation(Deck.reduceMotion ? nil : .default, value: symbol)
                Text(label).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(QuickChipStyle(on: on, filled: filled))
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

/// Quiet chip matching the tile fill; tinted when the toggle is on, or solid accent with white text when `filled`.
private struct QuickChipStyle: ButtonStyle {
    let on: Bool
    var filled = false
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .frame(height: 30)
            .foregroundStyle(on ? (filled ? Color.white : Color.accentColor) : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(on ? AnyShapeStyle(Color.accentColor.opacity(filled ? (hovering ? 0.9 : 1) : 0.18))
                             : AnyShapeStyle(.quaternary.opacity(hovering ? 0.9 : 0.55)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !Deck.reduceMotion ? 0.97 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }
}
