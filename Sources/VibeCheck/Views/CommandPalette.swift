import SwiftUI

/// ⌘K palette results inside the deck shell (the shell draws the search field and the key hints).
/// Typing goes through the deck's key monitor: the panel never takes focus from the user's app.
struct CommandPaletteView: View {
    @Environment(DeckModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let query = model.paletteQuery ?? ""
        let results = DeckCommands.filter(DeckCommands.all(model: model, settings: settings), query: query)
        Group {
            if results.isEmpty {
                Text("Nothing matches “\(query)”")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                        PaletteRow(command: command, selected: index == model.paletteIndex,
                                   confirming: model.paletteConfirmID == command.id,
                                   activate: { DeckCommands.activate(command, model: model) },
                                   onHover: { if !model.paletteActionsOpen { model.paletteIndex = index } })
                    }
                }
            }
        }
        .onAppear { QuickActions.shared.refresh() }
        .padding(.horizontal, -6)   // rows carry their own 6 pt inset; align their icons with the field's
        .overlay(alignment: .bottomTrailing) {
            if model.paletteActionsOpen, results.indices.contains(model.paletteIndex) {
                PaletteActionsCard(actions: DeckCommands.actions(for: results[model.paletteIndex], model: model))
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
        .animation(Deck.reduceMotion ? nil : .easeOut(duration: 0.14), value: model.paletteActionsOpen)
    }
}

/// ⌘↩ list for the selected row: Run, and the Settings pane that goes with it.
private struct PaletteActionsCard: View {
    let actions: [DeckCommand]
    @Environment(DeckModel.self) private var model

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                PaletteRow(command: action, selected: index == model.paletteActionIndex, confirming: false, compact: true,
                           activate: { model.paletteActionsOpen = false; action.run() },
                           onHover: { model.paletteActionIndex = index })
            }
        }
        .padding(4)
        .frame(width: 260)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.windowBackground))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
        .padding(.bottom, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions")
    }
}

/// One action row: tinted symbol, title, shortcut hint; the selected row shows ↩ instead of the hint.
private struct PaletteRow: View {
    let command: DeckCommand
    let selected: Bool
    let confirming: Bool
    var compact = false
    let activate: () -> Void
    let onHover: () -> Void

    var body: some View {
        Button(action: activate) {
            HStack(spacing: 9) {
                Image(systemName: command.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary.opacity(compact ? 0 : 0.7)))
                Text(confirming ? "\(command.title)? Press ↩ again" : command.title)
                    .font(.system(size: compact ? 12 : 13, weight: .medium))
                    .foregroundStyle(confirming ? Color.red : .primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                ZStack(alignment: .trailing) {
                    if let shortcut = command.shortcut { KeyCap(text: shortcut).opacity(selected ? 0 : 1) }
                    KeyCap(text: "↩").opacity(selected ? 1 : 0)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: compact ? 26 : 30)
            .background(RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous)
                .fill(Color.accentColor.opacity(selected ? 0.14 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Deck.reduceMotion ? nil : .easeOut(duration: 0.12), value: selected)
        .onHover { if $0 { onHover() } }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Small rounded key label: "esc", "⌘1", "↩".
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 17)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.quaternary.opacity(0.8)))
    }
}

/// Blinking text caret (steady with Reduce Motion).
struct Caret: View {
    var height: CGFloat = 16

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.55)) { context in
            let on = Deck.reduceMotion || Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor)
                .frame(width: 2, height: height)
                .opacity(on ? 1 : 0)
        }
    }
}
