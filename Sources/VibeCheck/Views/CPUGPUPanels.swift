import SwiftUI

struct CPUPanel: View {
    @Environment(SystemStats.self) private var stats

    var body: some View {
        let cpu = stats.cpu
        Panel(module: .cpu, headline: Fmt.percent(cpu.total),
              subtitle: String(localized: "User \(Fmt.percent(cpu.user)) · Sys \(Fmt.percent(cpu.system))")) {
            VibeStripView()
            MetricChart(lines: [.init(key: .cpu, color: Palette.user, name: "Total"),
                                .init(key: .cpuSystem, color: Palette.system, name: "Sys")],
                        maxValue: 1, height: 96, format: Fmt.percent)

            ProcessList(metric: .cpu)

            DetailsDisclosure(.cpu) {
                VStack(spacing: 4) {
                    StatRow(label: "User", value: Fmt.percent(cpu.user), color: Palette.user)
                    StatRow(label: "System", value: Fmt.percent(cpu.system), color: Palette.system)
                    StatRow(label: "Idle", value: Fmt.percent(cpu.idle), color: .gray.opacity(0.5))
                    if let p = cpu.performanceBusy, let e = cpu.efficiencyBusy {
                        StatRow(label: "Performance cores", value: Fmt.percent(p))
                        StatRow(label: "Efficiency cores", value: Fmt.percent(e))
                    }
                    if let power = stats.power, let line = Self.powerLine(power) {
                        StatRow(label: "Power", value: line)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(text: LocalizedStringKey(coreTitle))
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

    /// "CPU 3.2 W · GPU 0.8 W · Neural Engine 0.0 W", skipping parts that couldn't be read.
    static func powerLine(_ power: PowerReport) -> String? {
        let parts = [power.cpu.map { String(localized: "CPU \(PowerReport.label($0))") },
                     power.gpu.map { String(localized: "GPU \(PowerReport.label($0))") },
                     power.ane.map { String(localized: "Neural Engine \(PowerReport.label($0))") }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
        case .nominal: String(localized: "Nominal")
        case .fair: String(localized: "Fair")
        case .serious: String(localized: "Serious")
        case .critical: String(localized: "Critical")
        @unknown default: String(localized: "Unknown")
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
                            if sample.gpus.count > 1 { SectionTitle(text: LocalizedStringKey(gpu.model)) }
                            StatRow(label: "Utilization", value: Fmt.percent(gpu.device), color: Palette.gpu)
                            if let r = gpu.renderer { StatRow(label: "Renderer", value: Fmt.percent(r), color: Palette.user) }
                            if let t = gpu.tiler { StatRow(label: "Tiler", value: Fmt.percent(t), color: Palette.tiler) }
                            if let used = gpu.memoryInUse { StatRow(label: "Memory in use", value: Fmt.bytes(used)) }
                            if let alloc = gpu.memoryAllocated { StatRow(label: "Memory allocated", value: Fmt.bytes(alloc)) }
                        }
                    }
                    if let watts = stats.power?.gpu { StatRow(label: "Power", value: PowerReport.label(watts)) }
                }
            }
        }
    }
}

