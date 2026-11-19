import Foundation
import Observation

/// Keeps the latest agent usage sample; rescans the logs once a minute while the Agents module is on or
/// agent watch (keep awake while working, finished notification) needs it.
@Observable
@MainActor
final class AgentUsageStore {
    static let shared = AgentUsageStore()

    private(set) var sample = AgentUsageSample()
    @ObservationIgnored private var scanner = AgentUsageStore.makeScanner()
    /// Bumped when the Claude account changes, so a scan already running for the old one is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let queue = DispatchQueue(label: "vibecheck.agent-usage", qos: .utility)
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var scanning = false
    /// The last scan, before live Claude limits are merged in.
    @ObservationIgnored private var scanned = AgentUsageSample()

    func start() {
        guard timer == nil else { return }
        refresh()
        ClaudeLiveLimits.shared.start()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { AgentUsageStore.shared.refresh() }
        }
    }

    /// `fullWalk` also looks for new log files right away (otherwise that happens every 5 minutes).
    func refresh(fullWalk: Bool = false) {
        guard Self.isNeeded(AppSettings.shared), !scanning else { return }
        scanning = true
        let scanner = scanner, generation = generation
        let shown = Self.shownAgents()
        queue.async {
            let result = scanner.scan(fullWalk: fullWalk, shown: shown)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let store = AgentUsageStore.shared
                    store.scanning = false
                    guard generation == store.generation else { store.refresh(fullWalk: true); return }
                    // An agent was switched on or off while scanning: scan again with the new choice.
                    guard shown == Self.shownAgents() else { store.refresh(); return }
                    store.scanned = result
                    store.reapply()
                }
            }
        }
    }

    /// Agents switched on in Settings → Agents; the others are left out of everything the app shows.
    static func shownAgents() -> Set<AgentKind> {
        let options = AppSettings.shared.options(.agents)
        return Set(AgentKind.allCases.filter(options.includes))
    }

    /// A scanner reading the selected Claude Code account (other agents as usual).
    static func makeScanner() -> AgentUsageScanner {
        let profile = ClaudeProfiles.shared.selected
        let home = FileManager.default.homeDirectoryForCurrentUser
        return AgentUsageScanner(claudeRoots: profile.projectRoots(home: home), claudeConfig: profile.configFile(home: home))
    }

    /// Starts over with the newly selected Claude account's logs.
    func claudeProfileChanged() {
        generation += 1
        scanner = Self.makeScanner()
        refresh(fullWalk: true)
    }

    static func isNeeded(_ settings: AppSettings) -> Bool {
        settings.isEnabled(.agents) || settings.keepAwakeWhileAgentWorks || settings.notifyAgentFinished
    }

    /// Publishes the last scan with fresh live Claude limits merged in (only assigns when it changed).
    func reapply(now: Date = Date()) {
        let live = ClaudeLiveLimits.shared
        let merged = ClaudeLiveLimits.merge(scanned, live: live.currentWindows(now: now), fetchedAt: live.fetchedAt, now: now)
        if sample != merged { sample = merged }
    }
}
