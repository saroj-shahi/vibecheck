import AppIntents
import AppKit
import SwiftUI

// Shortcuts / Spotlight / Siri actions. They run inside the app (launching it in the background if needed).
// build.sh extracts their metadata with Xcode's appintentsmetadataprocessor; without that step Shortcuts
// doesn't see them.

enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case notRunning

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notRunning: "VibeCheck isn't ready yet. Try again in a moment."
        }
    }
}

@MainActor
enum IntentSupport {
    /// The app's live stats. Right after a cold launch, waits until a couple of samples exist.
    static func stats() async throws -> SystemStats {
        guard let delegate = NSApp.delegate as? AppDelegate else { throw IntentFailure.notRunning }
        let wait = 2.5 - Date().timeIntervalSince(delegate.launchedAt)
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        return delegate.stats
    }
}

// MARK: - Stats

enum StatKind: String, AppEnum {
    case cpu, gpu, memory, diskFree, download, upload, temperature, battery, agentTokens

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Stat"
    static let caseDisplayRepresentations: [StatKind: DisplayRepresentation] = [
        .cpu: "CPU usage",
        .gpu: "GPU usage",
        .memory: "Memory usage",
        .diskFree: "Free disk space",
        .download: "Download speed",
        .upload: "Upload speed",
        .temperature: "Hottest temperature",
        .battery: "Battery level",
        .agentTokens: "Agent tokens today",
    ]
}

/// A stat as a number (percent 0–100, bytes, bytes per second, °C or tokens) plus a sentence.
struct StatReading: Equatable {
    var value: Double
    var text: String

    @MainActor
    static func read(_ kind: StatKind, stats: SystemStats, agents: AgentUsageSample? = nil) -> StatReading? {
        let agents = agents ?? AgentUsageStore.shared.sample
        switch kind {
        case .cpu:
            return StatReading(value: stats.cpu.total * 100, text: String(localized: "CPU is at \(Fmt.percent(stats.cpu.total))."))
        case .gpu:
            guard !stats.gpu.gpus.isEmpty else { return nil }
            return StatReading(value: stats.gpu.utilization * 100, text: String(localized: "GPU is at \(Fmt.percent(stats.gpu.utilization))."))
        case .memory:
            return StatReading(value: stats.memory.usage * 100,
                               text: String(localized: "Memory is \(Fmt.percent(stats.memory.usage)) used, pressure \(stats.memory.pressure.label)."))
        case .diskFree:
            guard let volume = stats.volumes.first(where: { $0.path == "/" }) ?? stats.volumes.first else { return nil }
            return StatReading(value: volume.available, text: String(localized: "\(Fmt.bytes(volume.available)) free on \(volume.name)."))
        case .download:
            guard stats.network.interface != nil else { return StatReading(value: 0, text: String(localized: "You're offline.")) }
            return StatReading(value: stats.network.download, text: String(localized: "Downloading at \(Fmt.rate(stats.network.download))."))
        case .upload:
            guard stats.network.interface != nil else { return StatReading(value: 0, text: String(localized: "You're offline.")) }
            return StatReading(value: stats.network.upload, text: String(localized: "Uploading at \(Fmt.rate(stats.network.upload))."))
        case .temperature:
            guard let hottest = stats.sensors.hottest else { return nil }
            return StatReading(value: hottest, text: String(localized: "The hottest sensor is at \(String(format: "%.0f", hottest)) °C."))
        case .battery:
            let b = stats.battery
            guard b.present else { return nil }
            let state = b.isCharging ? String(localized: "charging") : b.onAC ? String(localized: "on power") : String(localized: "on battery")
            return StatReading(value: b.percent * 100, text: String(localized: "Battery is at \(Fmt.percent(b.percent)), \(state)."))
        case .agentTokens:
            guard agents.scanned, !agents.agents.isEmpty else { return nil }
            return StatReading(value: Double(agents.today.total),
                               text: String(localized: "Your coding agents used \(Fmt.tokens(agents.today.total)) tokens today."))
        }
    }
}

struct GetVibeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Mac Vibe"
    static let description = IntentDescription("Says whether your Mac is vibing, mid or cooked, and why.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let report = try await IntentSupport.stats().vibe
        return .result(value: report.vibe.title, dialog: "\(report.vibe.title). \(report.verdict)",
                       view: VibeSnippetView(vibe: report.vibe, verdict: report.verdict))
    }
}

struct GetStatIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Mac Stat"
    static let description = IntentDescription(
        "Reads one stat: a percentage for CPU, GPU, memory and battery; bytes for free disk; bytes per second for network; °C for temperature; a count for agent tokens.")

    @Parameter(title: "Stat", default: .cpu)
    var stat: StatKind

    static var parameterSummary: some ParameterSummary { Summary("Get \(\.$stat)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let stats = try await IntentSupport.stats()
        if stat == .agentTokens { AgentUsageStore.shared.refresh() }
        guard let reading = StatReading.read(stat, stats: stats) else {
            return .result(value: 0, dialog: "That stat isn't available on this Mac right now.")
        }
        return .result(value: reading.value, dialog: "\(reading.text)")
    }
}

// MARK: - Deck

enum DeckModuleOption: String, AppEnum {
    case cpu, gpu, memory, network, disk, sensors, battery, weather, clock, agents, todo

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Module"
    static let caseDisplayRepresentations: [DeckModuleOption: DisplayRepresentation] = [
        .cpu: "CPU", .gpu: "GPU", .memory: "Memory", .network: "Network", .disk: "Disk",
        .sensors: "Sensors", .battery: "Battery", .weather: "Weather", .clock: "Date & Time", .agents: "Agents",
        .todo: "To-do",
    ]

    var module: Module { Module(rawValue: rawValue)! }
}

struct OpenDeckIntent: AppIntent {
    static let title: LocalizedStringResource = "Open VibeCheck Deck"
    static let description = IntentDescription("Opens the deck under the menu bar, on the home grid or one module.")

    @Parameter(title: "Module")
    var module: DeckModuleOption?

    static var parameterSummary: some ParameterSummary { Summary("Open the deck on \(\.$module)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let delegate = NSApp.delegate as? AppDelegate else { throw IntentFailure.notRunning }
        delegate.openDeck(module?.module)
        return .result()
    }
}

// MARK: - Keep awake

struct StartKeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Keep Mac Awake"
    static let description = IntentDescription("Stops your Mac from idle-sleeping, for a number of minutes or until stopped.")

    @Parameter(title: "Minutes", description: "Leave empty to stay awake until you stop it.", inclusiveRange: (1, 1440))
    var minutes: Int?

    static var parameterSummary: some ParameterSummary { Summary("Keep Mac awake for \(\.$minutes) minutes") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        KeepAwake.shared.start(minutes: minutes ?? 0)
        let text = KeepAwake.shared.session.map { String(localized: "Staying awake \($0.remaining(now: Date()))." ) } ?? String(localized: "Couldn't start.")
        return .result(dialog: "\(text)")
    }
}

struct StopKeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Let Mac Sleep"
    static let description = IntentDescription("Ends the keep-awake session so your Mac can sleep as usual.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let wasActive = KeepAwake.shared.isActive
        KeepAwake.shared.stop()
        let message: LocalizedStringResource = wasActive ? "Done. Your Mac can sleep again." : "Your Mac wasn't being kept awake."
        return .result(dialog: IntentDialog(message))
    }
}

// MARK: - Culprits

enum CulpritMetric: String, AppEnum {
    case cpu, memory

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Measure"
    static let caseDisplayRepresentations: [CulpritMetric: DisplayRepresentation] = [
        .cpu: "CPU", .memory: "Memory",
    ]

    /// Memory when the vibe is blaming memory, CPU otherwise.
    nonisolated static func defaultMetric(culprit: Module?) -> CulpritMetric { culprit == .memory ? .memory : .cpu }
}

/// One app's share, as plain values (CPU in percent of one core, memory in bytes).
struct CulpritSummary: Equatable, Sendable {
    var name: String
    var cpu: Double
    var memory: Double
    var processCount: Int
}

struct CulpritEntity: TransientAppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Busy app"

    @Property(title: "Name") var name: String
    @Property(title: "CPU %") var cpu: Double
    @Property(title: "Memory bytes") var memoryBytes: Double
    @Property(title: "Processes") var processCount: Int

    init() {}

    init(_ summary: CulpritSummary) {
        name = summary.name
        cpu = summary.cpu
        memoryBytes = summary.memory
        processCount = summary.processCount
    }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

enum CulpritText {
    /// The busiest apps first, by `metric`, at most `count`.
    nonisolated static func top(_ apps: [CulpritSummary], metric: CulpritMetric, count: Int) -> [CulpritSummary] {
        let key: (CulpritSummary) -> Double = metric == .cpu ? { $0.cpu } : { $0.memory }
        return Array(apps.sorted { key($0) > key($1) }.prefix(max(1, min(10, count))))
    }

    /// "Chrome 42% CPU, Xcode 18%, Slack 6%." The first entry names the measure.
    nonisolated static func dialog(_ apps: [CulpritSummary], metric: CulpritMetric) -> String {
        guard !apps.isEmpty else { return String(localized: "Nothing is busy right now.") }
        let parts = apps.enumerated().map { index, app -> String in
            switch metric {
            case .cpu:
                let value = "\(Int(app.cpu.rounded()))%"
                return index == 0 ? "\(app.name) \(value) CPU" : "\(app.name) \(value)"
            case .memory:
                let value = Fmt.bytes(app.memory)
                return index == 0 ? "\(app.name) \(value) memory" : "\(app.name) \(value)"
            }
        }
        return parts.joined(separator: ", ") + "."
    }
}

struct ListTopCulpritsIntent: AppIntent {
    static let title: LocalizedStringResource = "List Busiest Apps"
    static let description = IntentDescription("Lists the apps using the most CPU or memory right now, with their helper processes added in.")

    @Parameter(title: "Measure", description: "Leave empty to follow what's slowing your Mac down.")
    var metric: CulpritMetric?

    @Parameter(title: "Count", default: 5, inclusiveRange: (1, 10))
    var count: Int

    static var parameterSummary: some ParameterSummary { Summary("List the \(\.$count) busiest apps by \(\.$metric)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[CulpritEntity]> & ProvidesDialog {
        let stats = try await IntentSupport.stats()
        let chosen = metric ?? CulpritMetric.defaultMetric(culprit: stats.vibe.culprit)
        let rows = stats.processes.isEmpty ? await ProcessSampler.fetch() : stats.processes
        let apps = SystemStats.groupByApp(rows) { _ in nil }.map {
            CulpritSummary(name: $0.name, cpu: $0.cpu, memory: $0.memory, processCount: $0.processCount)
        }
        let top = CulpritText.top(apps, metric: chosen, count: count)
        return .result(value: top.map(CulpritEntity.init), dialog: "\(CulpritText.dialog(top, metric: chosen))")
    }
}

// MARK: - Dev servers

/// One project's servers and the process identities to stop (from the sampled start times).
struct DevServerTarget: Equatable, Sendable {
    var name: String
    var ports: [Int]
    var identities: [ProcessKiller.Identity]
}

enum DevServerText {
    nonisolated static func targets(from ports: [ListeningPort], home: String, currentUID: uid_t) -> [DevServerTarget] {
        DevServers.projects(from: ports, home: home, currentUID: currentUID).map { project in
            var ids: [ProcessKiller.Identity] = []
            for port in project.ports {
                guard let d = port.details else { continue }
                let id = ProcessKiller.Identity(pid: port.pid, started: d.startedMicros)
                if !ids.contains(id) { ids.append(id) }
            }
            return DevServerTarget(name: project.name, ports: Array(Set(project.ports.map(\.port))).sorted(), identities: ids)
        }
    }

    private nonisolated static func label(_ t: DevServerTarget) -> String {
        "\(t.name) (\(t.ports.map(String.init).joined(separator: ", ")))"
    }

    nonisolated static let none = String(localized: "No dev servers are running.")

    /// "Stop 2 dev servers: web (3000), api (8080)?"
    nonisolated static func confirmation(_ targets: [DevServerTarget]) -> String {
        let list = targets.map(label).joined(separator: ", ")
        return targets.count == 1 ? String(localized: "Stop 1 dev server: \(list)?")
                                  : String(localized: "Stop \(targets.count) dev servers: \(list)?")
    }

    /// `failures` maps a project name to the reason it refused.
    nonisolated static func result(stopped: [String], refused: [(name: String, reason: String)]) -> String {
        var parts: [String] = []
        if !stopped.isEmpty { parts.append(String(localized: "Stopped \(stopped.joined(separator: ", ")).")) }
        for r in refused { parts.append(String(localized: "Couldn't stop \(r.name): \(r.reason).")) }
        return parts.isEmpty ? none : parts.joined(separator: " ")
    }
}

struct StopDevServersIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Dev Servers"
    static let description = IntentDescription("Asks your forgotten local dev servers to quit, after you confirm.")

    /// macOS 14 only has the call macOS 15 deprecated.
    @available(*, deprecated)
    private func confirmOnMacOS14(_ question: String) async throws {
        try await requestConfirmation(result: .result(dialog: "\(question)"))
    }

    @available(*, deprecated)
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await IntentSupport.stats()
        let found = await PortSampler.fetch()
        let targets = DevServerText.targets(from: found, home: NSHomeDirectory(), currentUID: getuid())
        guard !targets.isEmpty else { return .result(dialog: "\(DevServerText.none)") }
        let question = DevServerText.confirmation(targets)
        if #available(macOS 15, *) {
            try await requestConfirmation(actionName: .custom(acceptLabel: "Stop", acceptAlternatives: [], denyLabel: "Cancel",
                                                              denyAlternatives: [], destructive: true),
                                          dialog: "\(question)")
        } else {
            try await confirmOnMacOS14(question)
        }
        var stopped: [String] = []
        var refused: [(name: String, reason: String)] = []
        for target in targets {
            var failure: String?
            for id in target.identities {
                if case .failed(let text) = ProcessKiller.quit(id, mode: .quit), text != String(localized: "Already gone") {
                    failure = text
                }
            }
            if let failure { refused.append((target.name, failure)) } else { stopped.append(target.name) }
        }
        return .result(dialog: "\(DevServerText.result(stopped: stopped, refused: refused))")
    }
}

// MARK: - Calendar & World Clocks

struct JoinVideoCallIntent: AppIntent {
    static let title: LocalizedStringResource = "Join Video Call"
    static let description = IntentDescription("Joins your active video call or the next one starting within 15 minutes.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let store = CalendarStore.shared
        store.activate(requestAccess: false)
        guard store.access == .granted else {
            return .result(value: false, dialog: "Calendar access isn't enabled in VibeCheck.")
        }
        if let event = store.joinNextVideoCall(lookaheadMinutes: 15), let link = event.videoCall {
            return .result(value: true, dialog: "Joining \(event.title) on \(link.service.title).")
        }
        return .result(value: false, dialog: "No video call is starting in the next 15 minutes.")
    }
}

struct OpenCalendarDateIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Calendar Date"
    static let description = IntentDescription("Opens Apple Calendar at a specific date, or today if left empty.")

    @Parameter(title: "Date", description: "Leave empty to open today.")
    var date: Date?

    static var parameterSummary: some ParameterSummary { Summary("Open Calendar at \(\.$date)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        CalendarDateHelper.openCalendarApp(at: date ?? Date())
        return .result()
    }
}

struct GetWorldClockIntent: AppIntent {
    static let title: LocalizedStringResource = "Get World Clock Time"
    static let description = IntentDescription("Returns the current local time for one of your world clocks or any city / time zone.")

    @Parameter(title: "City or Time Zone", description: "e.g. Tokyo, London, UTC, or San Francisco.")
    var query: String

    static var parameterSummary: some ParameterSummary { Summary("Get time in \(\.$query)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let now = Date()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let saved = AppSettings.shared.clock.worldClocks.first(where: {
            $0.name.localizedCaseInsensitiveCompare(needle) == .orderedSame
                || $0.timeZoneID.localizedCaseInsensitiveCompare(needle) == .orderedSame
        }) {
            let formatted = saved.formattedTime(at: now)
            return .result(value: saved.iso8601String(at: now), dialog: "It's \(formatted) in \(saved.name) (\(saved.relativeDescription(at: now))).")
        }
        if let match = CityIndex.search(needle, limit: 1).first {
            let clock = WorldClock(name: match.name, timeZoneID: match.timeZoneID)
            let formatted = clock.formattedTime(at: now)
            return .result(value: clock.iso8601String(at: now), dialog: "It's \(formatted) in \(clock.name) (\(clock.relativeDescription(at: now))).")
        }
        return .result(value: "", dialog: "Couldn't find a city or time zone matching \(needle).")
    }
}

// MARK: - Spotlight and Siri phrases

struct VibeCheckShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GetVibeIntent(),
                    phrases: ["Check my Mac's vibe with \(.applicationName)", "How is my Mac doing in \(.applicationName)"],
                    shortTitle: "Mac Vibe", systemImageName: "waveform.path.ecg")
        AppShortcut(intent: StartKeepAwakeIntent(),
                    phrases: ["Keep my Mac awake with \(.applicationName)"],
                    shortTitle: "Keep Awake", systemImageName: "cup.and.saucer.fill")
        AppShortcut(intent: StopKeepAwakeIntent(),
                    phrases: ["Let my Mac sleep with \(.applicationName)"],
                    shortTitle: "Let Mac Sleep", systemImageName: "cup.and.saucer")
        AppShortcut(intent: ListTopCulpritsIntent(),
                    phrases: ["What's slowing my Mac down in \(.applicationName)", "Which apps are busiest in \(.applicationName)"],
                    shortTitle: "Busiest Apps", systemImageName: "list.number")
        AppShortcut(intent: StopDevServersIntent(),
                    phrases: ["Stop my dev servers with \(.applicationName)"],
                    shortTitle: "Stop Dev Servers", systemImageName: "stop.circle")
        AppShortcut(intent: JoinVideoCallIntent(),
                    phrases: ["Join my next video call with \(.applicationName)"],
                    shortTitle: "Join Video Call", systemImageName: "video.fill")
        AppShortcut(intent: OpenDeckIntent(),
                    phrases: ["Open the \(.applicationName) deck"],
                    shortTitle: "Open Deck", systemImageName: "square.grid.2x2")
    }
}
