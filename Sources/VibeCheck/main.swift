import AppKit

MainActor.assumeIsolated {
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
        print("DISK read \(Fmt.rate(d.readRate)) write \(Fmt.rate(d.writeRate))")
        for v in DiskMonitor.volumes() { print("     \(v.name): \(Fmt.bytes(v.available)) free of \(Fmt.bytes(v.total))") }
        print("BATT present \(b.present) \(Fmt.percent(b.percent)) charging \(b.isCharging) AC \(b.onAC) cycles \(b.cycleCount.map(String.init) ?? "-") health \(b.health.map(Fmt.percent) ?? "-") temp \(b.temperature.map { String(format: "%.1f", $0) } ?? "-") W \(b.powerWatts.map { String(format: "%.1f", $0) } ?? "-")")
        let sensors = SensorsMonitor().sample()
        for t in sensors.summary { print("TEMP \(t.name): \(String(format: "%.1f", t.celsius)) °C") }
        print("     \(sensors.all.count) raw sensors")
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
        print("UP   \(Fmt.uptime(SysctlReader.uptime()))")
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
