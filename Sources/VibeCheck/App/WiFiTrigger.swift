import CoreLocation
import CoreWLAN
import Foundation

/// Keep-awake trigger "while on Wi-Fi X". macOS 14+ only reveals the network name to apps with Location
/// permission, so that is requested only when the user switches the trigger on.
@MainActor
final class WiFiTrigger: NSObject, CLLocationManagerDelegate {
    static let shared = WiFiTrigger()

    /// Last network name read (nil: not on Wi-Fi, or no permission).
    private(set) var ssid: String?
    private var manager: CLLocationManager?
    private var lastRead = Date.distantPast
    private var reading = false

    /// Whether the current network is the wanted one. Exact name, ignoring surrounding spaces.
    nonisolated static func matches(current: String?, wanted: String) -> Bool {
        let wanted = wanted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let current, !wanted.isEmpty else { return false }
        return current == wanted
    }

    var authorized: Bool {
        guard let manager else { return false }
        return manager.authorizationStatus == .authorizedAlways
    }

    var denied: Bool {
        guard let manager else { return false }
        return manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    /// Asks for Location access (the system shows its prompt once).
    func requestAccess() {
        let manager = self.manager ?? CLLocationManager()
        manager.delegate = self
        self.manager = manager
        if manager.authorizationStatus == .notDetermined { manager.requestAlwaysAuthorization() }
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
        DispatchQueue.main.async { MainActor.assumeIsolated { WiFiTrigger.shared.refresh(force: true) } }
    }
}
