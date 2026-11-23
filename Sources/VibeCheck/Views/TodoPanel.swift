import AppKit
import SwiftUI

/// The To-do module: one Apple Reminders list. Header with the list name (menu to switch lists), an
/// "Add task" field, open tasks, then the last few completed ones. Opening it asks for Reminders access
/// the first time.
struct TodoPanel: View {
    @Environment(AppSettings.self) private var settings
    private var store: RemindersStore { .shared }

    var body: some View {
        let granted = store.access == .granted
        Panel(module: .todo, headline: granted && store.loaded ? "\(store.open.count)" : "—", subtitle: subtitle) {
            switch store.access {
            case .granted: TodoListView()
            case .notAsked: askView
            default: deniedView
            }
        }
        .onAppear { store.activate(requestAccess: true) }
    }

    private var subtitle: String? {
        guard store.access == .granted, store.loaded else { return nil }
        let due = store.dueNowCount
        if store.open.isEmpty { return String(localized: "All done") }
        return due > 0 ? String(localized: "open · \(due) due") : String(localized: "open")
    }

    private var askView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VibeCheck keeps your to-dos in Apple Reminders, so they sync with your other devices.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Button("Allow Access to Reminders") { store.activate(requestAccess: true) }
        }
    }

    private var deniedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.access == .restricted
                 ? "Reminders access is restricted on this Mac, so the to-do list can't be shown."
                 : "VibeCheck can't read Reminders. Turn VibeCheck on in System Settings › Privacy & Security › Reminders.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            if store.access != .restricted {
                Button("Open Privacy Settings") { RemindersStore.openPrivacySettings() }
            }
        }
    }
}

/// The list itself, once access is granted.
private struct TodoListView: View {
    @Environment(AppSettings.self) private var settings
    private var store: RemindersStore { .shared }
    @State private var newTitle = ""
    @FocusState private var addFocused: Bool
    @State private var returnKey = TodoReturnKey()
    /// Row whose delete button was pressed once and now asks to confirm.
    @State private var confirmingDelete: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            addField
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            if !store.loaded {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else if store.selectedList == nil {
                Text("No Reminders lists yet. Make one in the Reminders app.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                openTasks
                if !store.completed.isEmpty { completedTasks }
            }
        }
        .onChange(of: addFocused) { _, focused in
            if focused {
                returnKey.install(onReturn: { submit(); return true },
                                  onEscape: { guard !newTitle.isEmpty else { return false }; newTitle = ""; return true })
            } else {
                returnKey.remove()
            }
        }
        .onChange(of: store.wantsAddFocus, initial: true) { _, wants in
            guard wants else { return }
            store.wantsAddFocus = false
            DispatchQueue.main.async { addFocused = true }
        }
        .onDisappear { returnKey.remove() }
    }

    // MARK: Header

    private var header: some View {
        let selected = store.selectedList
        return HStack(spacing: 6) {
            Menu {
                ForEach(store.lists) { list in
                    Button {
                        settings.todo.listID = list.id
                    } label: {
                        if list.id == selected?.id { Label(list.title, systemImage: "checkmark") } else { Text(list.title) }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(color(selected)).frame(width: 8, height: 8)
                    Text(selected?.title ?? String(localized: "Reminders")).font(.headline).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Switch list")
            .accessibilityLabel("List: \(selected?.title ?? "")")
            Spacer()
            Button {
                if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
                    NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
                }
            } label: { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.borderless)
                .help("Open Reminders")
        }
    }

    private func color(_ list: TodoList?) -> Color {
        guard let list else { return .secondary }
        return Color(red: list.red, green: list.green, blue: list.blue)
    }

    // MARK: Add

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            TextField("Add task", text: $newTitle)
                .textFieldStyle(.plain)
                .focused($addFocused)
                .onSubmit(submit)
            if !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: submit) { KeyCap(text: "↩") }
                    .buttonStyle(.plain)
                    .help("Add task")
                    .accessibilityLabel("Add task")
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.6)))
    }

    private func submit() {
        let title = newTitle
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        newTitle = ""
        store.add(title: title)
    }

    // MARK: Rows

    @ViewBuilder
    private var openTasks: some View {
        if store.open.isEmpty {
            Text("Nothing to do.").font(.callout).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(store.open) { item in row(item) }
            }
        }
    }

    private var completedTasks: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionTitle(text: "Completed").padding(.top, 4).padding(.bottom, 2)
            ForEach(store.completed) { item in row(item) }
        }
    }

    private func row(_ item: TodoItem) -> some View {
        TodoRow(item: item, confirming: confirmingDelete == item.id,
                onToggle: { store.setCompleted(item, !item.completed) },
                onDelete: {
                    if confirmingDelete == item.id {
                        confirmingDelete = nil
                        store.delete(item)
                    } else {
                        confirmingDelete = item.id
                    }
                },
                onCancelDelete: { if confirmingDelete == item.id { confirmingDelete = nil } })
    }
}

/// One task: round checkbox, title, due date; delete on hover or right-click (asks once more inline).
private struct TodoRow: View {
    let item: TodoItem
    let confirming: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onCancelDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        let now = Date()
        let urgent = !item.completed && TodoLogic.bucket(item, now: now) <= .today
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.completed ? AnyShapeStyle(.secondary) : urgent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(item.completed ? "Mark as not done" : "Mark as done")
            .accessibilityLabel(item.completed ? "Mark \(item.title) as not done" : "Mark \(item.title) as done")

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .strikethrough(item.completed)
                    .foregroundStyle(item.completed ? .secondary : .primary)
                    .lineLimit(2)
                if !item.completed, let due = TodoLogic.dueText(item, now: now) {
                    Text(due).font(.caption)
                        .foregroundStyle(urgent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            if confirming {
                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .font(.caption.weight(.semibold))
                    .help("Delete this reminder")
            } else if hovering {
                Button(action: onDelete) { Image(systemName: "trash").font(.system(size: 11)) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Delete")
                    .accessibilityLabel("Delete \(item.title)")
            }
        }
        .opacity(item.completed ? 0.6 : 1)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear)))
        .onHover { hovering in
            self.hovering = hovering
            if !hovering { onCancelDelete() }
        }
        .contextMenu {
            Button(item.completed ? "Mark as Not Done" : "Mark as Done", action: onToggle)
            Button("Delete…", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: item.completed ? "Mark as not done" : "Mark as done", onToggle)
        .accessibilityAction(named: "Delete", onDelete)
    }
}

/// Return in the "Add task" field: the deck's own key monitor takes Return (and Escape) before the field
/// sees it, so while the field has focus a later monitor (macOS runs the newest first) handles them.
@MainActor
final class TodoReturnKey {
    private var monitor: Any?

    func install(onReturn: @escaping @MainActor () -> Bool, onEscape: @escaping @MainActor () -> Bool) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = event.keyCode
            let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            let handled = MainActor.assumeIsolated { () -> Bool in
                // Closing the deck only orders it out, so the field never loses focus and this monitor stays.
                // Only keys aimed at the visible deck are ours; Return in Settings or any other window passes.
                guard plain, let panel = event.window as? DeckPanel, panel.isVisible, panel.isKeyWindow else { return false }
                // Typing with an input method: Return confirms the composition, not the task.
                if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
                switch code {
                case 36, 76: return onReturn()
                case 53: return onEscape()
                default: return false
                }
            }
            return handled ? nil : event
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
