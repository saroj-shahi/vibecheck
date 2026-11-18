import AppKit
import Foundation
import Observation

struct History {
    let capacity: Int
    private(set) var values: [Double] = []

    init(capacity: Int) { self.capacity = capacity }

    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    func suffix(_ n: Int) -> [Double] { Array(values.suffix(n)) }
}

/// Single source of truth: samples every monitor on a timer and keeps short histories for graphs.
@Observable
@MainActor
final class SystemStats {
    nonisolated static let historyLength = 90

    private(set) var cpu = CPUSample()
    private(set) var cpuHistory = History(capacity: historyLength)
    private(set) var cpuSystemHistory = History(capacity: historyLength)
    private(set) var loadAverage: [Double] = [0, 0, 0]
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    private(set) var gpu = GPUSample()
    private(set) var gpuHistory = History(capacity: historyLength)

    private(set) var memory = MemorySample()
    private(set) var memoryHistory = History(capacity: historyLength)

    private(set) var network = NetworkSample()
    private(set) var downloadHistory = History(capacity: historyLength)
    private(set) var uploadHistory = History(capacity: historyLength)

    private(set) var disk = DiskSample()
    private(set) var readHistory = History(capacity: historyLength)
    private(set) var writeHistory = History(capacity: historyLength)
    private(set) var volumes: [VolumeInfo] = []

    private(set) var sensors = SensorsSample()
    private(set) var temperatureHistory = History(capacity: historyLength)

    private(set) var battery = BatterySample()
    private(set) var batteryHistory = History(capacity: historyLength)
    private(set) var devices: [DeviceBattery] = []
    @ObservationIgnored private var lastDeviceFetch: Date?
    @ObservationIgnored private var fetchingDevices = false
    private(set) var uptime: TimeInterval = 0
    private(set) var processes: [ProcessRow] = []
    private(set) var vibe = VibeReport(vibe: .vibing, verdict: "Checking the vibes…")
    @ObservationIgnored private var vibeTracker = VibeTracker()
    @ObservationIgnored var refreshInterval: TimeInterval = 2
    private(set) var networkApps: [AppNetworkUsage] = []
    @ObservationIgnored private var fetchingNetworkApps = false

    /// Number of open panels showing per-app network usage; `nettop` only runs while this is > 0.
    var networkAppDemand = 0 {
        didSet { if networkAppDemand > 0, oldValue == 0 { refreshNetworkApps() } }
    }

    let history = HistoryStore()
    /// Called after every sample; the app delegate hooks alerts in here.
    var onTick: (() -> Void)?

    let cpuMonitor = CPUMonitor()
    private let memoryMonitor = MemoryMonitor()
    private let networkMonitor = NetworkMonitor()
    private let diskMonitor = DiskMonitor()
    private let sensorsMonitor = SensorsMonitor()

    /// Number of open panels that list processes; `ps` only runs while this is > 0.
    var processDemand = 0 {
        didSet { if processDemand > 0, oldValue == 0 { refreshProcesses() } }
    }

    private var timer: Timer?
    private var tickCount = 0
    private var fetchingProcesses = false

    func start(interval: TimeInterval) {
        refreshInterval = interval
        timer?.invalidate()
        if tickCount == 0 { tick() }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        if let sample = cpuMonitor.sample() {
            cpu = sample
            cpuHistory.append(sample.total)
            cpuSystemHistory.append(sample.system)
        }
        loadAverage = CPUMonitor.loadAverage()
        thermalState = ProcessInfo.processInfo.thermalState

        gpu = GPUMonitor.sample()
        gpuHistory.append(gpu.utilization)

        memory = memoryMonitor.sample()
        memoryHistory.append(memory.usage)

        network = networkMonitor.sample()
        downloadHistory.append(network.download)
        uploadHistory.append(network.upload)

        disk = diskMonitor.sample()
        readHistory.append(disk.readRate)
        writeHistory.append(disk.writeRate)

        sensors = sensorsMonitor.sample()
        if let hottest = sensors.hottest { temperatureHistory.append(hottest) }

        // Slower-changing data refreshes every few ticks.
        if tickCount % 5 == 0 {
            volumes = DiskMonitor.volumes()
            battery = BatteryMonitor.sample()
            if battery.present { batteryHistory.append(battery.percent) }
            refreshDevicesIfDue()
            uptime = SysctlReader.uptime()
        }
        tickCount += 1

        var values: [HistoryKey: Double] = [
            .cpu: cpu.total, .cpuSystem: cpu.system, .memory: memory.usage,
            .download: network.download, .upload: network.upload,
            .read: disk.readRate, .write: disk.writeRate,
        ]
        if !gpu.gpus.isEmpty { values[.gpu] = gpu.utilization }
        if let hottest = sensors.hottest { values[.temperature] = hottest }
        if battery.present { values[.battery] = battery.percent }
        history.record(values)
        updateVibe()
        onTick?()

        if processDemand > 0 { refreshProcesses() }
        if networkAppDemand > 0 { refreshNetworkApps() }
    }

    var vibeInput: VibeInput {
        let window = max(1, Int((30 / max(refreshInterval, 0.5)).rounded()))
        let recent = cpuHistory.suffix(window)
        let startup = volumes.first { $0.path == "/" } ?? volumes.first
        return VibeInput(
            cpuRecent: recent.isEmpty ? cpu.total : recent.reduce(0, +) / Double(recent.count),
            memoryPressure: memory.pressure,
            hottest: sensors.hottest,
            startupDiskFree: startup.map { 1 - $0.usage },
            batteryOnBattery: battery.present && !battery.onAC ? battery.percent : nil,
            thermalState: thermalState)
    }

    private func updateVibe() {
        let input = vibeInput
        let level = vibeTracker.update(VibeScore.evaluate(input))
        let top = processes.isEmpty ? nil : topApps(by: \.cpu, limit: 1).first.map { ($0.name, $0.cpu) }
        let report = VibeReport(vibe: level, verdict: VibeScore.verdict(for: level, input: input, topApp: top))
        if report != vibe { vibe = report }
    }

    /// Bluetooth accessory levels change slowly; check once a minute in the background.
    private func refreshDevicesIfDue() {
        guard !fetchingDevices, lastDeviceFetch.map({ Date().timeIntervalSince($0) > 60 }) ?? true else { return }
        fetchingDevices = true
        lastDeviceFetch = Date()
        Task {
            let found = await DeviceBatteryMonitor.fetch()
            self.devices = found
            self.fetchingDevices = false
        }
    }

    private func refreshNetworkApps() {
        guard !fetchingNetworkApps else { return }
        fetchingNetworkApps = true
        Task {
            let rows = await NetworkAppSampler.fetch()
            self.networkApps = NetworkAppSampler.groupByApp(rows) { NSRunningApplication(processIdentifier: $0)?.localizedName }
            self.fetchingNetworkApps = false
        }
    }

    private func refreshProcesses() {
        guard !fetchingProcesses else { return }
        fetchingProcesses = true
        Task {
            let rows = await ProcessSampler.fetch()
            self.processes = rows
            self.fetchingProcesses = false
        }
    }

    /// Recent samples (one per refresh) for the "Live" chart range.
    func live(_ key: HistoryKey) -> [Double] {
        switch key {
        case .cpu: cpuHistory.values
        case .cpuSystem: cpuSystemHistory.values
        case .gpu: gpuHistory.values
        case .memory: memoryHistory.values
        case .temperature: temperatureHistory.values
        case .download: downloadHistory.values
        case .upload: uploadHistory.values
        case .read: readHistory.values
        case .write: writeHistory.values
        case .battery: batteryHistory.values
        }
    }

    func topProcesses(by key: KeyPath<ProcessRow, Double>, limit: Int = 5) -> [ProcessRow] {
        Array(processes.sorted { $0[keyPath: key] > $1[keyPath: key] }.prefix(limit))
    }

    /// Processes summed per responsible app, so Chrome or Slack show as one line with all their helpers.
    func topApps(by key: KeyPath<AppUsage, Double>, limit: Int = 5) -> [AppUsage] {
        Self.groupByApp(processes) { NSRunningApplication(processIdentifier: $0)?.localizedName }
            .sorted { $0[keyPath: key] > $1[keyPath: key] }
            .prefix(limit).map { $0 }
    }

    nonisolated static func groupByApp(_ rows: [ProcessRow], appName: (Int32) -> String?) -> [AppUsage] {
        let namesByPID = Dictionary(rows.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return Dictionary(grouping: rows, by: \.responsible).map { owner, members in
            AppUsage(id: owner,
                     name: appName(owner) ?? namesByPID[owner] ?? members[0].name,
                     cpu: members.reduce(0) { $0 + $1.cpu },
                     memory: members.reduce(0) { $0 + $1.memory },
                     processCount: members.count)
        }
    }
}
