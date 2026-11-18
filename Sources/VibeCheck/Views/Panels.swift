import SwiftUI

// MARK: - Shared building blocks

struct Panel<Content: View>: View {
    let module: Module
    let headline: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    @Environment(SystemStats.self) private var stats
    @Environment(\.deckNamespace) private var namespace
    @Environment(\.deckShowsBack) private var showsBack

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // In the deck the header row is pinned above the scroll view (DeckRoot draws it).
            if !showsBack { PanelHeader(module: module) }
            // Hero: the one number that answers "how is it doing?", with a short summary beside it.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headline)
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .tracking(-0.6)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .deckMatched("value.\(module.rawValue)", namespace)
                Spacer(minLength: 4)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
            }
            .padding(.top, -6)
            content
            Divider()
            HStack {
                Text("Up \(Fmt.uptime(stats.uptime))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    (NSApp.delegate as? AppDelegate)?.showSettings()
                } label: { Image(systemName: "gearshape") }
                    .help("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: { Image(systemName: "power") }
                    .help("Quit VibeCheck")
            }
            .buttonStyle(.borderless)
        }
        .padding([.horizontal, .bottom], 16)
        .padding(.top, showsBack ? 0 : 16)
        .frame(width: Deck.width)
        .background(
            // The tile's background grows into the whole detail view, fading as it goes.
            RoundedRectangle(cornerRadius: Deck.cornerRadius, style: .continuous)
                .fill(.clear)
                .deckMatched("bg.\(module.rawValue)", namespace)
        )
    }
}

/// Icon and title of a detail view; in the deck, a back chevron too.
struct PanelHeader: View {
    let module: Module
    var showsBack = false
    @Environment(SystemStats.self) private var stats
    @Environment(\.deckNamespace) private var namespace
    @Environment(DeckModel.self) private var deckModel: DeckModel?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if showsBack, let deckModel {
                DeckIconButton(symbol: "chevron.left", help: "Back (Esc)") { deckModel.go(.home) }
                    .padding(.leading, -6)
            }
            Image(systemName: module.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(module.accent)
                .networkStatusDot(online: stats.network.interface != nil, size: 6, enabled: module == .network)
                .deckMatched("icon.\(module.rawValue)", namespace)
            Text(module.title).font(.headline)
            Spacer()
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var color: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let color {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Secondary rows tucked behind a "Details" toggle; open/closed is remembered per module.
struct DetailsDisclosure<Content: View>: View {
    @AppStorage private var expanded: Bool
    private let content: Content

    init(_ module: Module, @ViewBuilder content: () -> Content) {
        _expanded = AppStorage(wrappedValue: false, "details.\(module.rawValue)")
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Deck.animation) { expanded.toggle() }
            } label: {
                HStack {
                    Text("Details").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Hide details" : "Show details")

            if expanded {
                VStack(alignment: .leading, spacing: 12) { content }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

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
        else { return }
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
private struct QuitMenuItems: View {
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
private struct QuitAccessibility<Actions: View>: ViewModifier {
    let pid: Int32
    @ViewBuilder let actions: () -> Actions

    func body(content: Content) -> some View {
        if let reason = ProcessKiller.protectionReason(pid: pid) {
            content.accessibilityHint("Can't be quit: \(reason.lowercased())")
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

/// "Listening ports": TCP listeners with their owner, quit through the same path as ProcessList.
struct ListeningPortsSection: View {
    @Environment(SystemStats.self) private var stats
    @State private var confirming: QuitConfirmation?
    @State private var notice: (pid: Int32, text: String)?
    @State private var noticeClear: Task<Void, Never>?
    @State private var showAll = false
    private let limit = 8

    var body: some View {
        let ports = stats.listeningPorts
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: "Listening ports")
            if ports.isEmpty {
                Text("Nothing is listening.").font(.callout).foregroundStyle(.tertiary)
            }
            ForEach(showAll ? Array(ports) : Array(ports.prefix(limit))) { row($0) }
            if ports.count > limit {
                Button {
                    withAnimation(Deck.animation) { showAll.toggle() }
                } label: {
                    Text(showAll ? "Show fewer" : "+\(ports.count - limit) more")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityHint(showAll ? "Shows the first \(limit) ports" : "Shows all \(ports.count) ports")
            }
        }
    }

    @ViewBuilder
    private func row(_ item: ListeningPort) -> some View {
        if let confirming, confirming.target.pid == item.pid, Date().timeIntervalSince(confirming.asked) < 20,
           ProcessKiller.identity(of: item.pid) == confirming.target {
            ForceQuitConfirmRow(name: ProcessKiller.name(of: item.pid) ?? item.name,
                                subprocesses: confirming.subprocesses,
                                cancel: { withAnimation(Deck.animation) { self.confirming = nil } },
                                confirm: { run(confirming.target, mode: .forceQuit,
                                               subprocesses: confirming.subprocesses) })
        } else {
            HStack(spacing: 6) {
                Group {
                    if let icon = NSRunningApplication(processIdentifier: item.pid)?.icon {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "gearshape").foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 16, height: 16)
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let notice, notice.pid == item.pid {
                    Text(notice.text).font(.caption).foregroundStyle(.orange).lineLimit(1)
                } else {
                    Text(item.isLocalOnly ? "local only" : "open to network")
                        .font(.caption).foregroundStyle(item.isLocalOnly ? .tertiary : .secondary)
                    Text(String(item.port)).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .contentShape(Rectangle())
            .help("\(item.address):\(item.port), pid \(item.pid)")
            .contextMenu { menu(item) }
            .modifier(QuitAccessibility(pid: item.pid, actions: { menu(item) }))
        }
    }

    private func menu(_ item: ListeningPort) -> some View {
        QuitMenuItems(pid: item.pid, rowName: item.name, run: run,
                      askForceQuit: { c in withAnimation(Deck.animation) { confirming = c } })
    }

    private func run(_ target: ProcessKiller.Identity, mode: ProcessKiller.Mode, subprocesses: Bool) {
        confirming = nil
        guard case .failed(let text) = ProcessKiller.quit(target, mode: mode, subprocesses: subprocesses)
        else { return }
        notice = (target.pid, text)
        noticeClear?.cancel()
        noticeClear = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { notice = nil }
        }
    }
}

// MARK: - Module panels

struct ModulePanel: View {
    let module: Module

    var body: some View {
        switch module {
        case .cpu: CPUPanel()
        case .gpu: GPUPanel()
        case .memory: MemoryPanel()
        case .network: NetworkPanel()
        case .disk: DiskPanel()
        case .sensors: SensorsPanel()
        case .battery: BatteryPanel()
        case .clock: ClockPanel()
        case .weather: WeatherPanel()
        case .agents: AgentsPanel()
        }
    }
}

struct CPUPanel: View {
    @Environment(SystemStats.self) private var stats

    var body: some View {
        let cpu = stats.cpu
        Panel(module: .cpu, headline: Fmt.percent(cpu.total),
              subtitle: "User \(Fmt.percent(cpu.user)) · Sys \(Fmt.percent(cpu.system))") {
            MetricChart(lines: [.init(key: .cpu, color: Palette.user, name: "Total"),
                                .init(key: .cpuSystem, color: Palette.system, name: "Sys")],
                        maxValue: 1, height: 96, format: Fmt.percent)

            ProcessList(metric: .cpu)

            DetailsDisclosure(.cpu) {
                VStack(spacing: 4) {
                    StatRow(label: "User", value: Fmt.percent(cpu.user), color: Palette.user)
                    StatRow(label: "System", value: Fmt.percent(cpu.system), color: Palette.system)
                    StatRow(label: "Idle", value: Fmt.percent(cpu.idle), color: .gray.opacity(0.5))
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(text: coreTitle)
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(cpu.perCore.enumerated()), id: \.offset) { _, usage in
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2).fill(.quaternary)
                                    .overlay(alignment: .bottom) {
                                        RoundedRectangle(cornerRadius: 2).fill(Palette.user)
                                            .frame(height: geo.size.height * CGFloat(usage))
                                    }
                            }
                        }
                    }
                    .frame(height: 32)
                }
                VStack(spacing: 4) {
                    StatRow(label: "Load average",
                            value: stats.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: "  "))
                    StatRow(label: "Thermal state", value: thermalLabel)
                }
            }
        }
    }

    private var coreTitle: String {
        let m = stats.cpuMonitor
        if m.performanceCores > 0, m.efficiencyCores > 0 {
            return "\(stats.cpu.perCore.count) cores · \(m.performanceCores)P + \(m.efficiencyCores)E"
        }
        return "\(stats.cpu.perCore.count) cores"
    }

    private var thermalLabel: String {
        switch stats.thermalState {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}

struct GPUPanel: View {
    @Environment(SystemStats.self) private var stats

    var body: some View {
        let sample = stats.gpu
        Panel(module: .gpu, headline: sample.gpus.isEmpty ? "—" : Fmt.percent(sample.utilization),
              subtitle: sample.gpus.first.map { gpu in gpu.cores.map { "\(gpu.model) · \($0) cores" } ?? gpu.model }) {
            MetricChart(lines: [.init(key: .gpu, color: Palette.gpu)], maxValue: 1, height: 96, format: Fmt.percent)

            if sample.gpus.isEmpty {
                Text("No GPU statistics available.").font(.callout).foregroundStyle(.secondary)
            } else {
                DetailsDisclosure(.gpu) {
                    ForEach(sample.gpus) { gpu in
                        VStack(alignment: .leading, spacing: 6) {
                            if sample.gpus.count > 1 { SectionTitle(text: gpu.model) }
                            StatRow(label: "Utilization", value: Fmt.percent(gpu.device), color: Palette.gpu)
                            if let r = gpu.renderer { StatRow(label: "Renderer", value: Fmt.percent(r), color: Palette.user) }
                            if let t = gpu.tiler { StatRow(label: "Tiler", value: Fmt.percent(t), color: Palette.tiler) }
                            if let used = gpu.memoryInUse { StatRow(label: "Memory in use", value: Fmt.bytes(used)) }
                            if let alloc = gpu.memoryAllocated { StatRow(label: "Memory allocated", value: Fmt.bytes(alloc)) }
                        }
                    }
                }
            }
        }
    }
}

struct MemoryPanel: View {
    @Environment(SystemStats.self) private var stats

    var body: some View {
        let m = stats.memory
        Panel(module: .memory, headline: Fmt.percent(m.usage),
              subtitle: "\(Fmt.bytes(m.used)) of \(Fmt.bytes(m.total))") {
            VStack(alignment: .leading, spacing: 6) {
                StackedBar(segments: [(m.app, Palette.app), (m.wired, Palette.wired),
                                      (m.compressed, Palette.compressed), (m.cached, Palette.cached)],
                           total: m.total)
                HStack(spacing: 5) {
                    Circle().fill(Palette.pressure(m.pressure)).frame(width: 7, height: 7)
                    Text("Pressure \(m.pressure.label.lowercased())")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            MetricChart(lines: [.init(key: .memory, color: Palette.app)], maxValue: 1, height: 64, format: Fmt.percent)

            ProcessList(metric: .memory)

            DetailsDisclosure(.memory) {
                VStack(spacing: 4) {
                    StatRow(label: "App memory", value: Fmt.bytes(m.app), color: Palette.app)
                    StatRow(label: "Wired", value: Fmt.bytes(m.wired), color: Palette.wired)
                    StatRow(label: "Compressed", value: Fmt.bytes(m.compressed), color: Palette.compressed)
                    StatRow(label: "Cached files", value: Fmt.bytes(m.cached), color: Palette.cached)
                    StatRow(label: "Free", value: Fmt.bytes(m.free))
                    StatRow(label: "Swap used",
                            value: m.swapTotal > 0 ? "\(Fmt.bytes(m.swapUsed)) of \(Fmt.bytes(m.swapTotal))" : "None")
                }
            }
        }
    }
}

struct NetworkPanel: View {
    @Environment(SystemStats.self) private var stats

    var body: some View {
        let n = stats.network
        Panel(module: .network, headline: n.interface == nil ? "Offline" : "↓ \(Fmt.compactRate(n.download))",
              subtitle: n.interface == nil ? nil : "↑ \(Fmt.rate(n.upload))\n\(statusText(n))") {
            MetricChart(lines: [.init(key: .upload, color: Palette.upload), .init(key: .download, color: Palette.download)],
                        mirrored: true, height: 96, format: Fmt.rate)

            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: "Who's responsible")
                let apps = stats.networkApps.prefix(5)
                if apps.isEmpty {
                    Text("No app traffic right now.").font(.callout).foregroundStyle(.tertiary)
                }
                ForEach(Array(apps)) { app in
                    HStack(spacing: 6) {
                        Group {
                            if let icon = NSRunningApplication(processIdentifier: app.id)?.icon {
                                Image(nsImage: icon).resizable()
                            } else {
                                Image(systemName: "gearshape").foregroundStyle(.tertiary)
                            }
                        }
                        .frame(width: 16, height: 16)
                        Text(app.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("↓ \(Fmt.compactRate(app.download))  ↑ \(Fmt.compactRate(app.upload))")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }

            ListeningPortsSection()

            DetailsDisclosure(.network) {
                VStack(spacing: 4) {
                    StatRow(label: "Status", value: statusText(n), color: statusColor(n))
                    StatRow(label: "Interface", value: n.interface ?? "—")
                    StatRow(label: "Local IP", value: n.ipv4 ?? "—")
                    StatRow(label: "Downloaded since boot", value: Fmt.bytes(Double(n.totalDownloaded)))
                    StatRow(label: "Uploaded since boot", value: Fmt.bytes(Double(n.totalUploaded)))
                }
                if n.interfaces.count > 1 {
                    VStack(spacing: 4) {
                        SectionTitle(text: "Interfaces").frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(n.interfaces.prefix(6)) { iface in
                            HStack(spacing: 6) {
                                Circle().fill(iface.isActive ? Color.green : Color.gray.opacity(0.4)).frame(width: 6, height: 6)
                                Text(iface.displayName).lineLimit(1).truncationMode(.tail)
                                Spacer()
                                Text("↓ \(Fmt.compactRate(iface.download))  ↑ \(Fmt.compactRate(iface.upload))")
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.callout)
                            .help("\(iface.bsdName): \(Fmt.bytes(Double(iface.totalIn))) in, \(Fmt.bytes(Double(iface.totalOut))) out since boot")
                        }
                    }
                }
            }
        }
    }

    private func statusText(_ n: NetworkSample) -> String {
        guard n.interface != nil else { return "Offline" }
        let up = n.upload >= MenuBarLabel.activeThreshold, down = n.download >= MenuBarLabel.activeThreshold
        switch (up, down) {
        case (true, true): return "Sending & receiving"
        case (true, false): return "Sending"
        case (false, true): return "Receiving"
        case (false, false): return "Idle"
        }
    }

    private func statusColor(_ n: NetworkSample) -> Color {
        guard n.interface != nil else { return .red }
        let active = max(n.upload, n.download) >= MenuBarLabel.activeThreshold
        return active ? .green : .gray
    }
}

struct DiskPanel: View {
    @Environment(SystemStats.self) private var stats

    var body: some View {
        let d = stats.disk
        let primary = stats.volumes.first { $0.path == "/" } ?? stats.volumes.first
        Panel(module: .disk, headline: primary.map { Fmt.percent($0.usage) } ?? "—",
              subtitle: primary.map { "\(Fmt.bytes($0.available)) free" }) {
            MetricChart(lines: [.init(key: .read, color: Palette.read, name: "R"),
                                .init(key: .write, color: Palette.write, name: "W")],
                        mirrored: true, height: 80, format: Fmt.rate)
            HStack {
                Text("Read \(Fmt.rate(d.readRate))").foregroundStyle(Palette.read)
                Spacer()
                Text("Write \(Fmt.rate(d.writeRate))").foregroundStyle(Palette.write)
            }
            .font(.caption.monospacedDigit())

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Volumes")
                ForEach(stats.volumes) { v in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(v.name).lineLimit(1)
                            Spacer()
                            Text("\(Fmt.bytes(v.available)) free").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.callout)
                        CapacityBar(fraction: v.usage, color: Palette.level(v.usage))
                            .help("\(Fmt.bytes(v.used)) of \(Fmt.bytes(v.total)) used")
                    }
                }
            }
        }
    }
}

struct SensorsPanel: View {
    @Environment(SystemStats.self) private var stats

    var body: some View {
        let s = stats.sensors
        Panel(module: .sensors, headline: s.hottest.map(celsius) ?? "—", subtitle: fanSummary(s)) {
            if s.summary.isEmpty && s.fans.isEmpty {
                Text("No sensors available on this Mac.").font(.callout).foregroundStyle(.secondary)
            }
            if s.hottest != nil {
                MetricChart(lines: [.init(key: .temperature, color: .orange)], maxValue: 105, height: 80,
                            format: { String(format: "%.0f °C", $0) })
            }
            if !s.summary.isEmpty {
                VStack(spacing: 4) {
                    ForEach(s.summary) { t in
                        StatRow(label: t.name, value: celsius(t.celsius), color: Palette.temperature(t.celsius))
                    }
                }
            }

            DetailsDisclosure(.sensors) {
                if !s.fans.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(text: s.fans.count == 1 ? "Fan" : "Fans")
                        ForEach(s.fans) { fan in
                            StatRow(label: s.fans.count == 1 ? "Speed" : "Fan \(fan.id + 1)",
                                    value: fan.rpm < 1 ? "Off" : String(format: "%.0f rpm", fan.rpm))
                            CapacityBar(fraction: fan.level, color: .cyan)
                            if let lo = fan.minRPM, let hi = fan.maxRPM {
                                Text(String(format: "Range %.0f–%.0f rpm", lo, hi)).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                if s.systemPower != nil || s.adapterPower != nil {
                    VStack(spacing: 4) {
                        SectionTitle(text: "Power").frame(maxWidth: .infinity, alignment: .leading)
                        if let w = s.systemPower { StatRow(label: "System total", value: String(format: "%.1f W", w)) }
                        if let w = s.adapterPower { StatRow(label: "From power adapter", value: String(format: "%.1f W", w)) }
                    }
                }
                if s.all.count > s.summary.count {
                    VStack(spacing: 3) {
                        SectionTitle(text: "All sensors (\(s.all.count))").frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(s.all) { t in StatRow(label: t.name, value: celsius(t.celsius)) }
                    }
                }
            }
        }
    }

    private func fanSummary(_ s: SensorsSample) -> String? {
        guard let fan = s.fans.first else { return nil }
        return fan.rpm < 1 ? "Fan off" : String(format: "Fan %.0f rpm", fan.rpm)
    }

    private func celsius(_ value: Double) -> String { String(format: "%.0f °C", value) }
}

struct DeviceBatteryRow: View {
    let device: DeviceBattery

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: device.symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(device.name).lineLimit(1).truncationMode(.tail)
            Spacer()
            if device.levels.isEmpty {
                Text("No battery info").foregroundStyle(.tertiary)
            } else {
                ForEach(Array(device.levels.enumerated()), id: \.offset) { _, level in
                    HStack(spacing: 2) {
                        if !level.label.isEmpty {
                            Text(level.label).foregroundStyle(.secondary)
                        }
                        Text("\(level.percent)%")
                            .monospacedDigit()
                            .foregroundStyle(level.percent <= 15 ? Color.red : Color.primary)
                    }
                }
            }
        }
        .font(.callout)
    }
}

struct BatteryPanel: View {
    @Environment(SystemStats.self) private var stats

    var body: some View {
        let b = stats.battery
        Panel(module: .battery, headline: b.present ? Fmt.percent(b.percent) : "AC",
              subtitle: b.present ? subtitle(b) : "No internal battery") {
            if b.present {
                CapacityBar(fraction: b.percent, color: b.percent < 0.2 ? .red : .green)
                MetricChart(lines: [.init(key: .battery, color: .green)], maxValue: 1, height: 64, format: Fmt.percent)
            }

            if !stats.devices.isEmpty {
                VStack(spacing: 6) {
                    SectionTitle(text: "Devices").frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(stats.devices) { device in DeviceBatteryRow(device: device) }
                }
            }

            USBDevicesSection()

            if b.present {
                DetailsDisclosure(.battery) {
                    VStack(spacing: 4) {
                        StatRow(label: "Power source", value: b.onAC ? "Power adapter" : "Battery")
                        StatRow(label: "State", value: stateLabel(b))
                        if let w = b.powerWatts, abs(w) > 0.05 {
                            StatRow(label: w > 0 ? "Charging at" : "Drawing", value: String(format: "%.1f W", abs(w)))
                        }
                    }
                    VStack(spacing: 4) {
                        SectionTitle(text: "Health").frame(maxWidth: .infinity, alignment: .leading)
                        if let h = b.health { StatRow(label: "Maximum capacity", value: Fmt.percent(h)) }
                        if let c = b.cycleCount { StatRow(label: "Cycle count", value: "\(c)") }
                        if let t = b.temperature { StatRow(label: "Temperature", value: String(format: "%.1f °C", t)) }
                        if let cond = b.condition { StatRow(label: "Condition", value: cond) }
                    }
                }
            }
        }
    }

    private func subtitle(_ b: BatterySample) -> String {
        if let mins = b.minutesRemaining {
            return "\(stateLabel(b)) · \(Fmt.minutes(mins)) \(b.isCharging ? "to full" : "left")"
        }
        return stateLabel(b)
    }

    private func stateLabel(_ b: BatterySample) -> String {
        if b.isCharging { return "Charging" }
        if b.isCharged || (b.onAC && b.percent >= 0.99) { return "Charged" }
        return b.onAC ? "Not charging" : "On battery"
    }
}

/// Connected USB devices, read every 5 s while this view is on screen.
struct USBDevicesSection: View {
    @State private var devices: [USBDevice] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionTitle(text: "USB devices")
                Spacer()
                if loaded, !devices.isEmpty {
                    Text("\(devices.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if loaded, devices.isEmpty {
                Text("No USB devices connected.").font(.callout).foregroundStyle(.tertiary)
            }
            ForEach(devices) { device in
                HStack(spacing: 6) {
                    Image(systemName: "cable.connector").foregroundStyle(.secondary).frame(width: 16)
                    Text(device.name).lineLimit(1)
                    Spacer()
                    if let vendor = device.vendor {
                        Text(vendor).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
            }
        }
        .task {
            while !Task.isCancelled {
                let found = await Task.detached(priority: .utility) { USBDeviceMonitor.devices() }.value
                if found != devices { devices = found }
                loaded = true
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}
