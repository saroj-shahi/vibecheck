import AppKit
import ServiceManagement

// Child processes (ps, lsof, nettop, claude) can exit early; a write to their pipe must not kill the app.
signal(SIGPIPE, SIG_IGN)

MainActor.assumeIsolated {
    // `VibeCheck --login-item on|off|status` manages launch at login for this app bundle, then exits.
    if let flag = CommandLine.arguments.firstIndex(of: "--login-item") {
        let action = CommandLine.arguments.dropFirst(flag + 1).first ?? "status"
        let service = SMAppService.mainApp
        do {
            switch action {
            case "on": try service.register()
            case "off": try service.unregister()
            default: break
            }
        } catch {
            print("error: \(error.localizedDescription)")
        }
        let status: String
        switch service.status {
        case .enabled: status = "enabled"
        case .notRegistered: status = "not registered"
        case .requiresApproval: status = "requires approval in System Settings > General > Login Items"
        case .notFound: status = "not found"
        @unknown default: status = "unknown"
        }
        print("login item (\(Bundle.main.bundlePath)): \(status)")
        exit(0)
    }

    // `VibeCheck --dump` prints one sample of every monitor and exits (handy for debugging).
    if CommandLine.arguments.contains("--dump") {
        let cpu = CPUMonitor()
        _ = cpu.sample(); let net = NetworkMonitor(); _ = net.sample(); let disk = DiskMonitor(); _ = disk.sample()
        Thread.sleep(forTimeInterval: 1)
        let c = cpu.sample(), m = MemoryMonitor().sample(), n = net.sample(), d = disk.sample()
        let b = BatteryMonitor.sample()
        print("CPU  total \(Fmt.percent(c?.total ?? -1)) user \(Fmt.percent(c?.user ?? 0)) sys \(Fmt.percent(c?.system ?? 0)) cores \(c?.perCore.count ?? 0) (\(cpu.performanceCores)P+\(cpu.efficiencyCores)E) load \(CPUMonitor.loadAverage())")
        for g in GPUMonitor.sample().gpus { print("GPU  \(g.model) cores \(g.cores ?? 0) device \(Fmt.percent(g.device)) renderer \(g.renderer.map(Fmt.percent) ?? "-") tiler \(g.tiler.map(Fmt.percent) ?? "-") mem \(g.memoryInUse.map(Fmt.bytes) ?? "-")") }
        print("MEM  used \(Fmt.bytes(m.used))/\(Fmt.bytes(m.total)) app \(Fmt.bytes(m.app)) wired \(Fmt.bytes(m.wired)) comp \(Fmt.bytes(m.compressed)) cached \(Fmt.bytes(m.cached)) pressure \(m.pressure.label) swap \(Fmt.bytes(m.swapUsed))")
        print("NET  \(n.interface ?? "-") \(n.ipv4 ?? "-") down \(Fmt.rate(n.download)) up \(Fmt.rate(n.upload)) totals \(Fmt.bytes(Double(n.totalDownloaded)))/\(Fmt.bytes(Double(n.totalUploaded)))")
        for i in n.interfaces.prefix(5) { print("     iface \(i.bsdName) \(i.displayName): ↓\(Fmt.rate(i.download)) ↑\(Fmt.rate(i.upload)) total \(Fmt.bytes(Double(i.totalIn)))") }
        print("DISK read \(Fmt.rate(d.readRate)) write \(Fmt.rate(d.writeRate))")
        print("BT   snooze available \(BluetoothSnooze.shared.isAvailable) access \(BluetoothSnooze.shared.access) controller \(BluetoothSnooze.shared.isPoweredOn.map { $0 ? "on" : "off" } ?? "-")")
        for v in DiskMonitor.volumes() { print("     \(v.name): \(Fmt.bytes(v.available)) free of \(Fmt.bytes(v.total))") }
        print("BATT present \(b.present) \(Fmt.percent(b.percent)) charging \(b.isCharging) AC \(b.onAC) cycles \(b.cycleCount.map(String.init) ?? "-") health \(b.health.map(Fmt.percent) ?? "-") temp \(b.temperature.map { String(format: "%.1f", $0) } ?? "-") W \(b.powerWatts.map { String(format: "%.1f", $0) } ?? "-")")
        let sensors = SensorsMonitor().sample()
        for t in sensors.summary { print("TEMP \(t.name): \(String(format: "%.1f", t.celsius)) °C") }
        print("     \(sensors.all.count) raw sensors, \(sensors.all.filter { SensorsMonitor.isSummarySensor($0.name) }.count) summary, \(sensors.all.filter { $0.name.contains("tdie") }.count) tdie")
        for f in sensors.fans { print("FAN  \(f.id): \(Int(f.rpm)) rpm (\(Int(f.minRPM ?? 0))–\(Int(f.maxRPM ?? 0)))") }
        print("PWR  system \(sensors.systemPower.map { String(format: "%.1f W", $0) } ?? "-") adapter \(sensors.adapterPower.map { String(format: "%.1f W", $0) } ?? "-")")
        let devices = DispatchSemaphore(value: 0)
        Task.detached {
            for d in await DeviceBatteryMonitor.fetch() {
                print("DEV  \(d.name) [\(d.kind ?? "?")] " + (d.levels.isEmpty ? "no battery info"
                    : d.levels.map { "\($0.label.isEmpty ? "" : $0.label + " ")\($0.percent)%" }.joined(separator: " ")))
            }
            devices.signal()
        }
        devices.wait()
        let extra = DispatchSemaphore(value: 0)
        Task.detached {
            let rows = await NetworkAppSampler.fetch()
            let apps = NetworkAppSampler.groupByApp(rows) { NSRunningApplication(processIdentifier: $0)?.localizedName }.prefix(4)
            print("APPS " + apps.map { "\($0.name) ↓\(Fmt.compactRate($0.download)) ↑\(Fmt.compactRate($0.upload))" }.joined(separator: " | "))
            if let f = try? await OpenMeteo.forecast(for: WeatherLocation(name: "London", region: nil, country: nil,
                                                                          latitude: 51.5085, longitude: -0.1257), unit: .celsius) {
                print("WX   London \(f.temperature)° \(WeatherCode.describe(f.code)), \(f.hours.count)h, \(f.days.count)d")
            } else { print("WX   fetch failed") }
            extra.signal()
        }
        extra.wait()
        let scanner = AgentUsageScanner()
        let started = Date()
        let usage = scanner.scan()
        let first = Date().timeIntervalSince(started)
        let again = Date()
        _ = scanner.scan()
        print("AGNT today \(Fmt.tokens(usage.today.total)) (in \(Fmt.tokens(usage.today.input)) out \(Fmt.tokens(usage.today.output)) cw \(Fmt.tokens(usage.today.cacheWrite)) cr \(Fmt.tokens(usage.today.cacheRead))) week \(Fmt.tokens(usage.week.total)) scan \(String(format: "%.2f", first))s, rescan \(String(format: "%.3f", Date().timeIntervalSince(again)))s")
        for a in usage.agents {
            print("     \(a.agent.title): today \(Fmt.tokens(a.today.total)) week \(Fmt.tokens(a.week.total)) window \(a.block.map { "\(Fmt.tokens($0.tokens.total)) until \($0.end.formatted(date: .omitted, time: .shortened))" } ?? "-") limits \(a.limits.map { "\($0.title) \($0.usedPercent)%" }) models \(a.modelsToday.prefix(3).map(\.name))")
        }
        print("     projects " + usage.projectsToday.prefix(4).map { "\($0.name) \(Fmt.tokens($0.tokens))" }.joined(separator: " | "))
        print("UP   \(Fmt.uptime(SysctlReader.uptime()))")
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
