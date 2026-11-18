import Foundation
import Observation

/// Keeps the latest agent usage sample; rescans the logs once a minute while the Agents module is on.
@Observable
@MainActor
final class AgentUsageStore {
    static let shared = AgentUsageStore()

    private(set) var sample = AgentUsageSample()
    @ObservationIgnored private let scanner = AgentUsageScanner()
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
        guard AppSettings.shared.isEnabled(.agents), !scanning else { return }
        scanning = true
        let scanner = scanner
        queue.async {
            let result = scanner.scan(fullWalk: fullWalk)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let store = AgentUsageStore.shared
                    store.scanning = false
                    store.scanned = result
                    store.reapply()
                }
            }
        }
    }

    /// Publishes the last scan with fresh live Claude limits merged in (only assigns when it changed).
    func reapply(now: Date = Date()) {
        let live = ClaudeLiveLimits.shared
        let merged = ClaudeLiveLimits.merge(scanned, live: live.currentWindows(now: now), fetchedAt: live.fetchedAt, now: now)
        if sample != merged { sample = merged }
    }
}
