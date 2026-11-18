import AppIntents
import AppKit

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
            return StatReading(value: stats.cpu.total * 100, text: "CPU is at \(Fmt.percent(stats.cpu.total)).")
        case .gpu:
            guard !stats.gpu.gpus.isEmpty else { return nil }
            return StatReading(value: stats.gpu.utilization * 100, text: "GPU is at \(Fmt.percent(stats.gpu.utilization)).")
        case .memory:
            return StatReading(value: stats.memory.usage * 100,
                               text: "Memory is \(Fmt.percent(stats.memory.usage)) used, pressure \(stats.memory.pressure.label).")
        case .diskFree:
            guard let volume = stats.volumes.first(where: { $0.path == "/" }) ?? stats.volumes.first else { return nil }
            return StatReading(value: volume.available, text: "\(Fmt.bytes(volume.available)) free on \(volume.name).")
        case .download:
            guard stats.network.interface != nil else { return StatReading(value: 0, text: "You're offline.") }
            return StatReading(value: stats.network.download, text: "Downloading at \(Fmt.rate(stats.network.download)).")
        case .upload:
            guard stats.network.interface != nil else { return StatReading(value: 0, text: "You're offline.") }
            return StatReading(value: stats.network.upload, text: "Uploading at \(Fmt.rate(stats.network.upload)).")
        case .temperature:
            guard let hottest = stats.sensors.hottest else { return nil }
            return StatReading(value: hottest, text: String(format: "The hottest sensor is at %.0f °C.", hottest))
        case .battery:
            let b = stats.battery
            guard b.present else { return nil }
            let state = b.isCharging ? "charging" : b.onAC ? "on power" : "on battery"
            return StatReading(value: b.percent * 100, text: "Battery is at \(Fmt.percent(b.percent)), \(state).")
        case .agentTokens:
            guard agents.scanned, !agents.agents.isEmpty else { return nil }
            return StatReading(value: Double(agents.today.total),
                               text: "Your coding agents used \(Fmt.tokens(agents.today.total)) tokens today.")
        }
    }
}

struct GetVibeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Mac Vibe"
    static let description = IntentDescription("Says whether your Mac is vibing, mid or cooked, and why.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let report = try await IntentSupport.stats().vibe
        return .result(value: report.vibe.title, dialog: "\(report.vibe.title). \(report.verdict)")
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
    case cpu, gpu, memory, network, disk, sensors, battery, weather, clock, agents

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Module"
    static let caseDisplayRepresentations: [DeckModuleOption: DisplayRepresentation] = [
        .cpu: "CPU", .gpu: "GPU", .memory: "Memory", .network: "Network", .disk: "Disk",
        .sensors: "Sensors", .battery: "Battery", .weather: "Weather", .clock: "Clock", .agents: "Agents",
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
        let text = KeepAwake.shared.session.map { "Staying awake \($0.remaining(now: Date()))." } ?? "Couldn't start."
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
        return .result(dialog: wasActive ? "Done. Your Mac can sleep again." : "Your Mac wasn't being kept awake.")
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
        AppShortcut(intent: OpenDeckIntent(),
                    phrases: ["Open the \(.applicationName) deck"],
                    shortTitle: "Open Deck", systemImageName: "square.grid.2x2")
    }
}
