import SwiftUI

struct NetworkPanel: View {
    @Environment(SystemStats.self) private var stats

    var body: some View {
        let n = stats.network
        Panel(module: .network, headline: n.interface == nil ? String(localized: "Offline") : "↓ \(Fmt.compactRate(n.download))",
              subtitle: n.interface == nil ? nil : String(localized: "↑ \(Fmt.rate(n.upload))\n\(statusText(n))")) {
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

            let hour = stats.appTraffic.top(limit: 5, now: Date())
            if !hour.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(text: "Last hour")
                    ForEach(hour) { app in
                        HStack(spacing: 6) {
                            Text(app.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text("↓ \(Fmt.bytes(app.download))  ↑ \(Fmt.bytes(app.upload))")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }

            ListeningPortsSection()

            DetailsDisclosure(.network) {
                VStack(spacing: 4) {
                    StatRow(label: "Status", value: statusText(n), color: statusColor(n))
                    StatRow(label: "Interface", value: n.interface ?? "—")
                    StatRow(label: "Local IP", value: n.ipv4 ?? "—")
                    if AppSettings.shared.showPublicIP {
                        StatRow(label: "Public IP", value: stats.publicIP ?? "—")
                    }
                    if let w = stats.wifi {
                        StatRow(label: "Wi-Fi", value: w.ssid ?? String(localized: "Hidden without Location access"))
                        StatRow(label: "Signal", value: String(localized: "\(w.rssi) dBm, noise \(w.noise) dBm"))
                        if let c = w.channel { StatRow(label: "Channel", value: [String(c), w.band].compactMap { $0 }.joined(separator: ", ")) }
                        if let p = w.phyMode { StatRow(label: "Standard", value: p) }
                        StatRow(label: "Link speed", value: String(localized: "\(Int(w.transmitRate)) Mbps"))
                    }
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
        guard n.interface != nil else { return String(localized: "Offline") }
        let up = n.upload >= MenuBarLabel.activeThreshold, down = n.download >= MenuBarLabel.activeThreshold
        switch (up, down) {
        case (true, true): return String(localized: "Sending & receiving")
        case (true, false): return String(localized: "Sending")
        case (false, true): return String(localized: "Receiving")
        case (false, false): return String(localized: "Idle")
        }
    }

    private func statusColor(_ n: NetworkSample) -> Color {
        guard n.interface != nil else { return .red }
        let active = max(n.upload, n.download) >= MenuBarLabel.activeThreshold
        return active ? .green : .gray
    }
}

struct ListeningPortsSection: View {
    @Environment(SystemStats.self) private var stats
    @State private var confirming: QuitConfirmation?
    @State private var notice: (pid: Int32, text: String)?
    @State private var noticeClear: Task<Void, Never>?
    @State private var showAll = false
    private let limit = 8

    var body: some View {
        let all = stats.listeningPorts
        let projects = DevServers.projects(from: all, home: NSHomeDirectory(), currentUID: getuid())
        let devKeys = Set(projects.flatMap { $0.ports.map(\.id) })
        let ports = all.filter { !devKeys.contains($0.id) }
        VStack(alignment: .leading, spacing: 4) {
            if !projects.isEmpty {
                DevServersGroup(projects: projects)
                    .padding(.bottom, 4)
            }
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


/// "Dev servers": local servers started from a project folder, grouped by project, with a Stop button.
struct DevServersGroup: View {
    let projects: [DevProject]
    @State private var showAll = false
    private let limit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: "Dev servers")
            ForEach(showAll ? projects : Array(projects.prefix(limit))) { DevProjectRow(project: $0) }
            if projects.count > limit {
                Button {
                    withAnimation(Deck.animation) { showAll.toggle() }
                } label: {
                    Text(showAll ? "Show fewer" : "+\(projects.count - limit) more")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct DevProjectRow: View {
    let project: DevProject
    @Environment(SystemStats.self) private var stats
    private enum Phase: Equatable { case running, stopping, stillRunning, failed(String) }
    @State private var phase = Phase.running
    @State private var targets: [ProcessKiller.Identity] = []
    @State private var stillRunningSince: Date?
    @State private var work: Task<Void, Never>?

    var body: some View {
        let uptime = DevServers.uptimeText(started: project.startedSeconds)
        let long = DevServers.isLongRunning(started: project.startedSeconds)
        let portText = project.ports.map { String($0.port) }.joined(separator: ", ")
        let showForce = phase == .stillRunning && forceStillValid
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(project.name).lineLimit(1).truncationMode(.middle)
                Text(project.runtimes.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if showForce {
                Text("Still running. Force stop?").font(.caption).foregroundStyle(.orange).lineLimit(1)
                Button("Force stop") { forceStop() }
                    .buttonStyle(.borderless).font(.caption.weight(.medium))
                    .accessibilityLabel("Force stop \(project.name)")
            } else if case .failed(let text) = phase {
                Text(text).font(.caption).foregroundStyle(.orange).lineLimit(1)
            } else {
                Text(portText).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(uptime).font(.caption).foregroundStyle(long ? .secondary : .tertiary)
                    .frame(minWidth: 36, alignment: .trailing)
                if let bytes = project.footprint {
                    Text(Fmt.bytes(Double(bytes))).font(.caption).foregroundStyle(.tertiary)
                }
                Button("Stop") { stop() }
                    .buttonStyle(.borderless).font(.caption.weight(.medium))
                    .disabled(phase == .stopping)
                    .accessibilityLabel("Stop \(project.name) on port \(project.ports.first?.port ?? 0)")
            }
        }
        .font(.callout)
        .help(project.folder)
        .onDisappear { work?.cancel() }
    }

    /// "Force stop?" only holds for 20 s, and only while the project still runs the pids that were stopped.
    private var forceStillValid: Bool {
        guard let since = stillRunningSince, Date().timeIntervalSince(since) < 20 else { return false }
        return targets.contains { t in project.ports.contains { $0.pid == t.pid && $0.details?.startedMicros == t.started } }
    }

    private func refreshIfOpen() {
        if stats.networkAppDemand > 0 { stats.refreshPorts() }
    }

    private func stop() {
        // Identity comes from the sampled start time, so a recycled pid is never signalled.
        var unique: [ProcessKiller.Identity] = []
        for port in project.ports {
            guard let d = port.details else { continue }
            let id = ProcessKiller.Identity(pid: port.pid, started: d.startedMicros)
            if !unique.contains(id) { unique.append(id) }
        }
        targets = unique
        stillRunningSince = nil
        phase = .stopping
        var failure: String?
        for t in unique {
            if case .failed(let text) = ProcessKiller.quit(t, mode: .quit), text != String(localized: "Already gone") {
                failure = text
            }
        }
        work?.cancel()
        if let failure {
            phase = .failed(failure)
            work = Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { phase = .running }
            }
            return
        }
        work = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            refreshIfOpen()
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return }
            if targets.contains(where: { ProcessKiller.identity(of: $0.pid) == $0 }) {
                stillRunningSince = Date()
                phase = .stillRunning
                try? await Task.sleep(for: .seconds(20))
                if !Task.isCancelled, phase == .stillRunning { phase = .running }
            } else {
                phase = .running
            }
        }
    }

    private func forceStop() {
        stillRunningSince = nil
        phase = .stopping
        for t in targets where ProcessKiller.identity(of: t.pid) == t { ProcessKiller.quit(t, mode: .forceQuit) }
        work?.cancel()
        work = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            refreshIfOpen()
            phase = .running
        }
    }
}
