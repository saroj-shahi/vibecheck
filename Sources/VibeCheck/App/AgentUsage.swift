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

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { AgentUsageStore.shared.refresh() }
        }
    }

    func refresh() {
        guard AppSettings.shared.isEnabled(.agents), !scanning else { return }
        scanning = true
        let scanner = scanner
        queue.async {
            let result = scanner.scan()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let store = AgentUsageStore.shared
                    store.scanning = false
                    if store.sample != result { store.sample = result }
                }
            }
        }
    }
}
