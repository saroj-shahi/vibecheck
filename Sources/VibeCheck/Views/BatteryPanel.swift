import SwiftUI

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
        Panel(module: .battery, headline: b.present ? Fmt.percent(b.percent) : String(localized: "AC"),
              subtitle: b.present ? subtitle(b) : String(localized: "No internal battery")) {
            if b.present {
                CapacityBar(fraction: b.percent, color: b.percent < 0.2 ? .red : .green)
                MetricChart(lines: [.init(key: .battery, color: .green)], maxValue: 1, height: 64, format: Fmt.percent)
                BatteryHistorySection()
                EnergyLeaderboard()
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
                        StatRow(label: "Power source", value: b.onAC ? String(localized: "Power adapter") : String(localized: "Battery"))
                        StatRow(label: "State", value: stateLabel(b))
                        if b.onAC, let cw = b.chargerWatts {
                            StatRow(label: "Charger", value: "\(cw) W")
                            if BatteryMonitor.isChargingSlowly(b) {
                                Text("Charging slowly").font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
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
            return b.isCharging ? String(localized: "\(stateLabel(b)) · \(Fmt.minutes(mins)) to full") : String(localized: "\(stateLabel(b)) · \(Fmt.minutes(mins)) left")
        }
        return stateLabel(b)
    }

    private func stateLabel(_ b: BatterySample) -> String {
        if b.isCharging { return String(localized: "Charging") }
        if b.isCharged || (b.onAC && b.percent >= 0.99) { return String(localized: "Charged") }
        return b.onAC ? String(localized: "Not charging") : String(localized: "On battery")
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

