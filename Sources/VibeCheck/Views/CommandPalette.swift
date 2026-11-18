import SwiftUI

/// ⌘K palette inside the deck: a search row and up to eight actions. Typing goes through the deck's key
/// monitor (the panel never takes focus from the user's app), so the query is drawn, not a text field.
struct CommandPaletteView: View {
    @Environment(DeckModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let query = model.paletteQuery ?? ""
        let results = DeckCommands.filter(DeckCommands.all(model: model, settings: settings), query: query)
        VStack(alignment: .leading, spacing: 0) {
            searchRow(query)
            Divider().opacity(0.6)
            if results.isEmpty {
                Text("Nothing matches “\(query)”")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 44, alignment: .leading)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                        PaletteRow(command: command, selected: index == model.paletteIndex,
                                   confirming: model.paletteConfirmID == command.id,
                                   activate: { DeckCommands.activate(command, model: model) },
                                   onHover: { model.paletteIndex = index })
                    }
                }
                .padding(.vertical, 6)
            }
            footer
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private func searchRow(_ query: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 1) {
                if query.isEmpty {
                    Caret()
                    Text("Search actions")
                        .foregroundStyle(.tertiary)
                } else {
                    Text(query)
                    Caret()
                }
            }
            .font(.system(size: 14))
            .lineLimit(1)
            Spacer(minLength: 4)
            KeyCap(text: "esc")
        }
        .frame(height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(query.isEmpty ? "Search actions" : "Search actions, \(query)")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            hint("↑↓", "choose")
            hint("↩", "run")
            hint("⌘K", "close")
            Spacer()
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            KeyCap(text: key)
            Text(label).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}

/// One action row: tinted symbol, title, shortcut hint; the selected row shows ↩ instead of the hint.
private struct PaletteRow: View {
    let command: DeckCommand
    let selected: Bool
    let confirming: Bool
    let activate: () -> Void
    let onHover: () -> Void

    var body: some View {
        Button(action: activate) {
            HStack(spacing: 9) {
                Image(systemName: command.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary.opacity(0.7)))
                Text(confirming ? "\(command.title)? Press ↩ again" : command.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(confirming ? Color.red : .primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                ZStack(alignment: .trailing) {
                    if let shortcut = command.shortcut { KeyCap(text: shortcut).opacity(selected ? 0 : 1) }
                    KeyCap(text: "↩").opacity(selected ? 1 : 0)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
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
private struct Caret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.55)) { context in
            let on = Deck.reduceMotion || Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor)
                .frame(width: 2, height: 16)
                .opacity(on ? 1 : 0)
        }
    }
}
