import CoreLocation
import CoreWLAN
import Foundation
import Observation

/// Keep-awake trigger "while on Wi-Fi X". macOS 14+ only reveals the network name to apps with Location
/// permission, so that is requested only when the user switches the trigger on.
@Observable
@MainActor
final class WiFiTrigger: NSObject, CLLocationManagerDelegate {
    static let shared = WiFiTrigger()

    /// Last network name read (nil: not on Wi-Fi, or no permission).
    private(set) var ssid: String?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @ObservationIgnored private var manager: CLLocationManager?
    @ObservationIgnored private var lastRead = Date.distantPast
    @ObservationIgnored private var reading = false

    /// Whether the current network is the wanted one. Exact name, ignoring surrounding spaces.
    nonisolated static func matches(current: String?, wanted: String) -> Bool {
        let wanted = wanted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let current, !wanted.isEmpty else { return false }
        return current == wanted
    }

    /// Reads the current authorization status without prompting, so Settings sees a prior grant/denial after relaunch.
    private func ensureManager() -> CLLocationManager {
        if let manager { return manager }
        let created = CLLocationManager()
        created.delegate = self
        manager = created
        authorization = created.authorizationStatus
        return created
    }

    var authorized: Bool {
        _ = ensureManager()
        return authorization == .authorizedAlways
    }

    var denied: Bool {
        _ = ensureManager()
        return authorization == .denied || authorization == .restricted
    }

    /// Asks for Location access (the system shows its prompt once).
    func requestAccess() {
        let manager = ensureManager()
        authorization = manager.authorizationStatus
        if authorization == .notDetermined { manager.requestAlwaysAuthorization() }
        refresh(force: true)
    }

    /// Re-reads the network name in the background (at most every 10 seconds) and then re-checks keep-awake triggers.
    func refresh(force: Bool = false, now: Date = Date()) {
        guard !reading, force || now.timeIntervalSince(lastRead) >= 10 else { return }
        reading = true
        lastRead = now
        Task.detached {
            let name = CWWiFiClient.shared().interface()?.ssid()
            await MainActor.run {
                let me = WiFiTrigger.shared
                let changed = me.ssid != name
                me.ssid = name
                me.reading = false
                if changed { KeepAwake.shared.check() }
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let me = WiFiTrigger.shared
                me.authorization = status
                me.refresh(force: true)
            }
        }
    }
}
