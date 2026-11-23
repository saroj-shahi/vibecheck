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
    private(set) var vibe = VibeReport(vibe: .vibing, verdict: String(localized: "Checking the vibes…"))
    @ObservationIgnored private var vibeTracker = VibeTracker()
    /// Per-module levels from the previous sample (vibe hysteresis).
    @ObservationIgnored private var vibeHeld: [Module: Vibe] = [:]
    /// Recent swap use, to tell active swapping from swap left over from earlier.
    @ObservationIgnored private var swapSamples: [(date: Date, used: Double)] = []
    @ObservationIgnored var refreshInterval: TimeInterval = 2
    private(set) var networkApps: [AppNetworkUsage] = []
    @ObservationIgnored private var fetchingNetworkApps = false
    private(set) var wifi: WiFiInfo?
    private(set) var publicIP: String?
    private(set) var appTraffic = AppTrafficHistory()
    @ObservationIgnored private var lastNetworkAppSample: Date?
    @ObservationIgnored private var fetchingWiFi = false
    @ObservationIgnored private var lastWiFiFetch = Date.distantPast
    @ObservationIgnored private var fetchingPublicIP = false
    @ObservationIgnored private var lastPublicIPFetch: Date?
    @ObservationIgnored private var lastNetworkKey: String?
    private(set) var listeningPorts: [ListeningPort] = []
    @ObservationIgnored private var fetchingPorts = false
    @ObservationIgnored private var lastPortFetch = Date.distantPast

    /// Number of open panels showing per-app network usage; `nettop` only runs while this is > 0.
    var networkAppDemand = 0 {
        didSet {
            if networkAppDemand > 0, oldValue == 0 { refreshNetworkApps(); refreshPorts() }
            if networkAppDemand == 0 { listeningPorts = [] }
        }
    }

    let history = HistoryStore()
    let vibeReplay = VibeReplayStore()
    let batteryLog = BatteryLogStore()
    /// Called after every sample; the app delegate hooks alerts in here.
    var onTick: (() -> Void)?

    let cpuMonitor = CPUMonitor()
    private let memoryMonitor = MemoryMonitor()
    private let networkMonitor = NetworkMonitor()
    private let diskMonitor = DiskMonitor()
    private let sensorsMonitor = SensorsMonitor()

    /// Number of open panels that list processes; `ps` only runs while this is > 0.
    var processDemand = 0 {
        didSet {
            if processDemand > 0, oldValue == 0 { refreshProcesses() }
            if processDemand == 0 { processes = [] } // stale lists only cost memory and verdict work
        }
    }
    /// Seconds between `ps` runs while processes are wanted: the deck home only needs the loudest app
    /// for its verdict, detail views list processes and refresh every tick.
    var processInterval: TimeInterval = 0
    @ObservationIgnored private var lastProcessFetch = Date.distantPast
    @ObservationIgnored private var lastSensorRead = Date.distantPast

    /// Number of open views listing every temperature sensor; otherwise only the summary sensors are read.
    var sensorDemand = 0 {
        didSet { if sensorDemand > 0, oldValue == 0 { sensors = sensorsMonitor.sample(allSensors: true) } }
    }

    private var timer: Timer?
    private var tickCount = 0
    private var fetchingProcesses = false

    @ObservationIgnored private var baseInterval: TimeInterval = 2
    @ObservationIgnored private var suspendReasons: Set<TickSuspendReason> = []
    @ObservationIgnored private var observersInstalled = false

    func start(interval: TimeInterval) {
        // Called on every settings change; only a new interval (or no timer yet) needs a new timer.
        let unchanged = interval == baseInterval && observersInstalled
        baseInterval = interval
        installObserversIfNeeded()
        if tickCount == 0 { tick() }
        if unchanged, timer != nil || !suspendReasons.isEmpty { return }
        reschedule()
    }

    /// Someone is clicking VibeCheck, so nothing can be asleep or locked: a safety net for a missed
    /// wake / unlock notification, which would otherwise leave the tick stopped.
    func userIsHere() {
        guard !suspendReasons.isEmpty else { return }
        suspendReasons.removeAll()
        resumed()
    }

    /// Lock and console state from the window server, not from notification pairing (distributed
    /// notifications can be dropped). Run on every wake, unlock and session switch back.
    private func resyncSession() {
        let dict = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        let wasSuspended = !suspendReasons.isEmpty
        if dict["CGSSessionScreenIsLocked"] as? Bool ?? false { suspendReasons.insert(.screenLocked) }
        else { suspendReasons.remove(.screenLocked) }
        if dict[kCGSessionOnConsoleKey as String] as? Bool ?? true { suspendReasons.remove(.sessionInactive) }
        else { suspendReasons.insert(.sessionInactive) }
        reschedule()
        if wasSuspended, suspendReasons.isEmpty { resumed() }
    }

    /// Back from a pause: forget the pre-pause app traffic timestamp and take fresh numbers now.
    private func resumed() {
        lastNetworkAppSample = nil
        reschedule()
        tick()
    }

    /// (Re)creates the timer for the current reasons, Low Power Mode and keep-awake state.
    private func reschedule() {
        timer?.invalidate()
        timer = nil
        let interval = TickPolicy.interval(base: baseInterval, reasons: suspendReasons,
                                           lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                           keepAwakeSession: KeepAwake.shared.isActive)
        TickGate.set(interval == nil)
        guard let interval else { return }
        refreshInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func setReason(_ reason: TickSuspendReason, _ on: Bool) {
        let wasSuspended = !suspendReasons.isEmpty
        if on { suspendReasons.insert(reason) } else { suspendReasons.remove(reason) }
        if !on { resyncSession(); return } // also clears a lock / switch whose own "off" was missed
        reschedule()
        if wasSuspended, suspendReasons.isEmpty { resumed() }
    }

    private func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let pairs: [(NotificationCenter, Notification.Name, TickSuspendReason, Bool)] = [
            (workspace, NSWorkspace.screensDidSleepNotification, .displayAsleep, true),
            (workspace, NSWorkspace.screensDidWakeNotification, .displayAsleep, false),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, .sessionInactive, true),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive, false),
            (distributed, Notification.Name("com.apple.screenIsLocked"), .screenLocked, true),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), .screenLocked, false),
        ]
        for (center, name, reason, on) in pairs {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setReason(reason, on) }
            }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resyncSession() }
        }
        // Low Power Mode changes the pace; a keep-awake session starting or ending changes whether a pause may fully stop.
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reschedule() }
        }
        NotificationCenter.default.addObserver(forName: .vibeCheckKeepAwakeChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reschedule() }
        }
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
        refreshNetworkExtrasIfDue()

        disk = diskMonitor.sample()
        readHistory.append(disk.readRate)
        writeHistory.append(disk.writeRate)

        // Temperatures change slowly: read at most every 4 s, except while the Sensors panel is open.
        if sensorDemand > 0 || Date().timeIntervalSince(lastSensorRead) >= 3.9 {
            sensors = sensorsMonitor.sample(allSensors: sensorDemand > 0)
            lastSensorRead = Date()
        }
        if let hottest = sensors.hottest { temperatureHistory.append(hottest) }

        // Slower-changing data refreshes every few ticks.
        if tickCount % 5 == 0 {
            volumes = DiskMonitor.volumes()
            battery = BatteryMonitor.sample()
            if battery.present { batteryHistory.append(battery.percent); batteryLog.record(battery) }
            // `system_profiler` once a minute is the most expensive sample: only when something shows it.
            if Self.needsDevices(batteryOn: AppSettings.shared.isEnabled(.battery), rules: AppSettings.shared.alertRules) {
                refreshDevicesIfDue()
            } else if !devices.isEmpty {
                devices = []
            }
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

        if processDemand > 0, Date().timeIntervalSince(lastProcessFetch) >= processInterval - 0.25 { refreshProcesses() }
        if networkAppDemand > 0 {
            refreshNetworkApps()
            if Date().timeIntervalSince(lastPortFetch) >= 4.75 { refreshPorts() }
        }
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
            thermalState: thermalState,
            swapGrowth: Self.swapGrowth(swapSamples),
            batteryMinutesLeft: battery.present && !battery.onAC && !battery.isCharging ? battery.minutesRemaining : nil,
            held: vibeHeld)
    }

    /// Swap added between the oldest and newest sample (the last ~60 s); 0 when flat or shrinking.
    nonisolated static func swapGrowth(_ samples: [(date: Date, used: Double)]) -> Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return max(0, last.used - first.used)
    }

    private func recordSwap(now: Date = Date()) {
        swapSamples.append((now, memory.swapUsed))
        swapSamples.removeAll { now.timeIntervalSince($0.date) > 60 }
    }

    private func updateVibe() {
        recordSwap()
        let input = vibeInput
        vibeHeld = VibeScore.held(input)
        let level = vibeTracker.update(VibeScore.evaluate(input))
        // Only while a view wants processes (the list is empty otherwise).
        let top = processDemand == 0 || processes.isEmpty ? nil : topApps(by: \.cpu, limit: 1).first.map { ($0.name, $0.cpu) }
        let report = VibeReport(vibe: level, verdict: VibeScore.verdict(for: level, input: input, topApp: top),
                                culprit: VibeScore.culprit(for: level, input: input),
                                badge: VibeScore.badge(for: level, input: input))
        if report != vibe { vibe = report }
        vibeReplay.observe(level: level, culprit: report.culprit, process: top?.0)
    }

    /// Accessory batteries are shown by the Battery module and checked by "Accessory battery" alerts.
    nonisolated static func needsDevices(batteryOn: Bool, rules: [AlertRule]) -> Bool {
        batteryOn || rules.contains { $0.enabled && $0.metric == .accessoryBattery }
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

    /// Wi-Fi details (panel open only, every 5 s) and the opt-in public IP (every 10 min and on network change).
    private func refreshNetworkExtrasIfDue() {
        let now = Date()
        if networkAppDemand > 0, !fetchingWiFi, now.timeIntervalSince(lastWiFiFetch) >= 5 {
            fetchingWiFi = true
            lastWiFiFetch = now
            Task.detached {
                let info = WiFiReader.read()
                await MainActor.run { self.wifi = info; self.fetchingWiFi = false }
            }
        }
        let key = "\(network.interface ?? "")|\(network.ipv4 ?? "")"
        let changed = key != lastNetworkKey
        lastNetworkKey = key
        guard AppSettings.shared.showPublicIP else { publicIP = nil; lastPublicIPFetch = nil; return }
        guard network.interface != nil else { publicIP = nil; return }
        if !fetchingPublicIP, PublicIPFetcher.isDue(lastFetch: lastPublicIPFetch, now: now, networkChanged: changed) {
            fetchingPublicIP = true
            lastPublicIPFetch = now
            Task {
                let ip = await PublicIPFetcher.fetch()
                if AppSettings.shared.showPublicIP { self.publicIP = ip }
                self.fetchingPublicIP = false
            }
        }
    }

    private func refreshNetworkApps() {
        guard !fetchingNetworkApps else { return }
        fetchingNetworkApps = true
        Task {
            let rows = await NetworkAppSampler.fetch()
            self.networkApps = NetworkAppSampler.groupByApp(rows) { NSRunningApplication(processIdentifier: $0)?.localizedName }
            let now = Date()
            // History only grows while the panel is open (that's when nettop runs).
            let gap = self.lastNetworkAppSample.map { now.timeIntervalSince($0) } ?? 1
            self.lastNetworkAppSample = now
            // After a pause the gap says nothing about the rate; skip that one sample rather than guess.
            if gap <= 10 { self.appTraffic.record(self.networkApps, seconds: min(gap, 5), now: now) }
            self.fetchingNetworkApps = false
        }
    }

    /// `lsof` for listening TCP ports, at most every 5 s and only while the Network view is open.
    private func refreshPorts() {
        guard !fetchingPorts else { return }
        fetchingPorts = true
        lastPortFetch = Date()
        Task {
            let found = await PortSampler.fetch()
            if self.networkAppDemand > 0 { self.listeningPorts = found }
            self.fetchingPorts = false
        }
    }

    private func refreshProcesses() {
        guard !fetchingProcesses else { return }
        fetchingProcesses = true
        lastProcessFetch = Date()
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
        // Rank with process names, then ask LaunchServices for the display name of the winners only.
        Self.groupByApp(processes) { _ in nil }
            .sorted { $0[keyPath: key] > $1[keyPath: key] }
            .prefix(limit)
            .map { app in
                guard let name = NSRunningApplication(processIdentifier: app.id)?.localizedName else { return app }
                return AppUsage(id: app.id, name: name, cpu: app.cpu, memory: app.memory, processCount: app.processCount)
            }
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
