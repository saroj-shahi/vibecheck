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
    @Environment(DeckModel.self) private var deckModel: DeckModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                if showsBack, let deckModel {
                    DeckIconButton(symbol: "chevron.left", help: "Back (Esc)") { deckModel.go(.home) }
                        .padding(.leading, -6)
                }
                Image(systemName: module.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(module.accent)
                    .deckMatched("icon.\(module.rawValue)", namespace)
                Text(module.title).font(.headline)
                Spacer()
            }
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
        .padding(16)
        .frame(width: Deck.width)
        .background(
            // The tile's background grows into the whole detail view, fading as it goes.
            RoundedRectangle(cornerRadius: Deck.cornerRadius, style: .continuous)
                .fill(.clear)
                .deckMatched("bg.\(module.rawValue)", namespace)
        )
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
                    row(name: app.name, detail: app.processCount > 1 ? "\(app.processCount)" : nil,
                        value: value(cpu: app.cpu, memory: app.memory),
                        icon: NSRunningApplication(processIdentifier: app.id)?.icon)
                }
            } else {
                let rows = metric == .cpu ? stats.topProcesses(by: \.cpu) : stats.topProcesses(by: \.memory)
                ForEach(rows) { row in
                    self.row(name: row.name, detail: nil, value: value(cpu: row.cpu, memory: row.memory), icon: nil)
                }
            }
        }
    }

    private func value(cpu: Double, memory: Double) -> String {
        metric == .cpu ? String(format: "%.1f%%", cpu) : Fmt.bytes(memory)
    }

    private func row(name: String, detail: String?, value: String, icon: NSImage?) -> some View {
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
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.callout)
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
        }
    }
}

struct CPUPanel: View {
    @Environment(SystemStats.self) private var stats

    var body: some View {
        let cpu = stats.cpu
        Panel(module: .cpu, headline: Fmt.percent(cpu.total),
              subtitle: "User \(Fmt.percent(cpu.user)) · Sys \(Fmt.percent(cpu.system))") {
            MetricChart(lines: [.init(key: .cpu, color: Palette.user),
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
