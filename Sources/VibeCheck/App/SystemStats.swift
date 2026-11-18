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
    private(set) var uptime: TimeInterval = 0
    private(set) var processes: [ProcessRow] = []

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
        onTick?()

        if processDemand > 0 { refreshProcesses() }
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
}
