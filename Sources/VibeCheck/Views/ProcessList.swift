import SwiftUI

struct ProcessList: View {
    enum Metric { case cpu, memory }
    let metric: Metric
    @Environment(SystemStats.self) private var stats
    @AppStorage("groupProcessesByApp") private var byApp = true
    /// Process waiting for a Force Quit confirmation, and when it was asked (it expires).
    @State private var confirming: QuitConfirmation?
    /// Short result shown in a row after a failed quit.
    @State private var notice: (pid: Int32, text: String)?
    @State private var noticeClear: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionTitle(text: "Who's responsible")
                Spacer()
                Picker("Group", selection: $byApp) {
                    Text("Apps").tag(true)
                    Text("Processes").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.mini).fixedSize()
            }
            if stats.processes.isEmpty {
                Text("Loading…").font(.callout).foregroundStyle(.tertiary)
            } else if byApp {
                let apps = metric == .cpu ? stats.topApps(by: \.cpu) : stats.topApps(by: \.memory)
                ForEach(apps) { app in
                    row(pid: app.id, name: app.name, detail: app.processCount > 1 ? "\(app.processCount)" : nil,
                        value: value(cpu: app.cpu, memory: app.memory),
                        icon: NSRunningApplication(processIdentifier: app.id)?.icon)
                }
            } else {
                let rows = metric == .cpu ? stats.topProcesses(by: \.cpu) : stats.topProcesses(by: \.memory)
                ForEach(rows) { row in
                    self.row(pid: row.id, name: row.name, detail: nil,
                             value: value(cpu: row.cpu, memory: row.memory), icon: nil)
                }
            }
        }
        .onChange(of: byApp) { confirming = nil; notice = nil }
    }

    private func value(cpu: Double, memory: Double) -> String {
        metric == .cpu ? String(format: "%.1f%%", cpu) : Fmt.bytes(memory)
    }

    @ViewBuilder
    private func row(pid: Int32, name: String, detail: String?, value: String, icon: NSImage?) -> some View {
        if let confirming, confirming.target.pid == pid, Date().timeIntervalSince(confirming.asked) < 20,
           ProcessKiller.identity(of: pid) == confirming.target {
            confirmRow(confirming, name: name)
        } else {
            HStack(spacing: 6) {
                if byApp {
                    Group {
                        if let icon { Image(nsImage: icon).resizable() }
                        else { Image(systemName: "gearshape").foregroundStyle(.tertiary) }
                    }
                    .frame(width: 16, height: 16)
                }
                Text(name).lineLimit(1).truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(.quaternary))
                        .help("\(detail) processes")
                }
                Spacer()
                if let notice, notice.pid == pid {
                    Text(notice.text).font(.caption).foregroundStyle(.orange).lineLimit(1)
                } else {
                    Text(value).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .contentShape(Rectangle())
            .contextMenu { menu(pid: pid, name: name) }
            .modifier(QuitAccessibility(pid: pid, actions: { menu(pid: pid, name: name) }))
        }
    }

    private func menu(pid: Int32, name rowName: String) -> some View {
        QuitMenuItems(pid: pid, rowName: rowName, run: run,
                      askForceQuit: { c in withAnimation(Deck.animation) { confirming = c } })
    }

    private func confirmRow(_ confirmation: QuitConfirmation, name rowName: String) -> some View {
        ForceQuitConfirmRow(name: ProcessKiller.name(of: confirmation.target.pid) ?? rowName,
                            subprocesses: confirmation.subprocesses,
                            cancel: { withAnimation(Deck.animation) { confirming = nil } },
                            confirm: { run(confirmation.target, mode: .forceQuit, subprocesses: confirmation.subprocesses) })
    }

    private func run(_ target: ProcessKiller.Identity, mode: ProcessKiller.Mode, subprocesses: Bool) {
        confirming = nil
        guard case .failed(let text) = ProcessKiller.quit(target, mode: mode, subprocesses: subprocesses)
        else {
            CulpritDrain.shared.start(culpritPresent: stats.vibe.culprit != nil)
            return
        }
        notice = (target.pid, text)
        noticeClear?.cancel()
        noticeClear = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { notice = nil }
        }
    }
}

/// A pending Force Quit, shown inline in the row; it expires after 20 s.
struct QuitConfirmation {
    let target: ProcessKiller.Identity
    let subprocesses: Bool
    let asked = Date()
}

/// Quit / Force Quit menu items (context menu and VoiceOver actions) shared by the process and port lists.
/// Plain processes with children also get "and subprocesses" (a CLI's children outlive a quit parent).
struct QuitMenuItems: View {
    let pid: Int32
    let rowName: String
    let run: (ProcessKiller.Identity, ProcessKiller.Mode, Bool) -> Void
    let askForceQuit: (QuitConfirmation) -> Void

    var body: some View {
        let name = ProcessKiller.name(of: pid) ?? rowName
        if let reason = ProcessKiller.protectionReason(pid: pid) {
            Text("Can't quit \(name): \(reason.lowercased())")
        } else if let target = ProcessKiller.identity(of: pid) {
            // The identity is taken when the menu is built, so a reused pid is refused at click time.
            Button("Quit \(name)") { run(target, .quit, false) }
            Button("Force Quit \(name)…") { askForceQuit(QuitConfirmation(target: target, subprocesses: false)) }
            if ProcessKiller.offersSubprocesses(pid: pid) {
                Divider()
                Button("Quit \(name) and Subprocesses") { run(target, .quit, true) }
                Button("Force Quit \(name) and Subprocesses…") {
                    askForceQuit(QuitConfirmation(target: target, subprocesses: true))
                }
            }
        }
    }
}

/// VoiceOver: quit actions on rows that can be quit; the reason as a hint on rows that can't.
struct QuitAccessibility<Actions: View>: ViewModifier {
    let pid: Int32
    @ViewBuilder let actions: () -> Actions

    func body(content: Content) -> some View {
        if let reason = ProcessKiller.protectionReason(pid: pid) {
            content.accessibilityHint(String(localized: "Can't be quit: \(reason.lowercased())"))
        } else {
            content.accessibilityActions { actions() }
        }
    }
}

/// Inline "Force quit X?" confirmation shared by the process and port lists.
struct ForceQuitConfirmRow: View {
    let name: String
    var subprocesses = false
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("Force quit \(name)\(subprocesses ? " and its subprocesses" : "")? Unsaved work is lost.")
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
            Button("Force Quit", action: confirm)
                .tint(.red)
        }
        .font(.callout)
        .controlSize(.small)
        .buttonStyle(.borderedProminent)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.red.opacity(0.12)))
    }
}

