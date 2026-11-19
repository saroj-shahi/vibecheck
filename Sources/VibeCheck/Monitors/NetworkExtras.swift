import CoreWLAN
import Foundation

/// Wi-Fi link details from CoreWLAN. `ssid` is nil without Location access.
struct WiFiInfo: Equatable {
    var ssid: String?
    var rssi: Int
    var noise: Int
    var channel: Int?
    var band: String?
    var phyMode: String?
    var transmitRate: Double   // Mbps

    var snr: Int { rssi - noise }

    nonisolated static func bandName(_ band: CWChannelBand?) -> String? {
        switch band {
        case .band2GHz: "2.4 GHz"
        case .band5GHz: "5 GHz"
        case .band6GHz: "6 GHz"
        default: nil
        }
    }

    nonisolated static func phyName(_ mode: CWPHYMode?) -> String? {
        switch mode {
        case .mode11a: "802.11a"
        case .mode11b: "802.11b"
        case .mode11g: "802.11g"
        case .mode11n: String(localized: "Wi-Fi 4 (802.11n)")
        case .mode11ac: String(localized: "Wi-Fi 5 (802.11ac)")
        case .mode11ax: String(localized: "Wi-Fi 6 (802.11ax)")
        default: nil
        }
    }
}

enum WiFiReader {
    /// Blocking CoreWLAN reads: call off the main thread. Nil when there's no Wi-Fi interface or it's off.
    nonisolated static func read() -> WiFiInfo? {
        guard let iface = CWWiFiClient.shared().interface(), iface.powerOn(), iface.rssiValue() != 0 else { return nil }
        let channel = iface.wlanChannel()
        return WiFiInfo(ssid: iface.ssid(), rssi: iface.rssiValue(), noise: iface.noiseMeasurement(),
                        channel: channel?.channelNumber, band: WiFiInfo.bandName(channel?.channelBand),
                        phyMode: WiFiInfo.phyName(iface.activePHYMode()), transmitRate: iface.transmitRate())
    }
}

/// Opt-in public IP lookup. Contacts `endpoint` (api.ipify.org) and nothing else.
enum PublicIPFetcher {
    static let endpoint = URL(string: "https://api.ipify.org")!
    static let minInterval: TimeInterval = 600

    /// Accepts only a plain IPv4 / IPv6 literal, so a captive-portal page never shows up as an address.
    nonisolated static func parse(_ body: String) -> String? {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 45 else { return nil }
        var v4 = in_addr(), v6 = in6_addr()
        if inet_pton(AF_INET, text, &v4) == 1 || inet_pton(AF_INET6, text, &v6) == 1 { return text }
        return nil
    }

    /// Whether a new lookup is due: never fetched, the network changed, or the last one is 10 minutes old.
    nonisolated static func isDue(lastFetch: Date?, now: Date, networkChanged: Bool) -> Bool {
        guard let lastFetch else { return true }
        return networkChanged || now.timeIntervalSince(lastFetch) >= minInterval
    }

    static func fetch() async -> String? {
        var request = URLRequest(url: endpoint, timeoutInterval: 8)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let body = String(data: data, encoding: .utf8) else { return nil }
        return parse(body)
    }
}

/// Per-app bytes at minute resolution for the last hour, in memory.
struct AppTrafficHistory {
    struct Entry: Identifiable, Equatable {
        let name: String
        var download: Double
        var upload: Double
        var id: String { name }
        var total: Double { download + upload }
    }

    static let window = 60
    private(set) var minutes: [Int: [String: (down: Double, up: Double)]] = [:]

    /// Adds `seconds` worth of the given rates, to the minute containing `now`.
    mutating func record(_ apps: [AppNetworkUsage], seconds: Double, now: Date) {
        guard seconds > 0 else { return }
        let minute = Int(now.timeIntervalSince1970 / 60)
        var bucket = minutes[minute] ?? [:]
        for app in apps {
            let old = bucket[app.name] ?? (0, 0)
            bucket[app.name] = (old.down + app.download * seconds, old.up + app.upload * seconds)
        }
        minutes[minute] = bucket
        minutes = minutes.filter { $0.key > minute - Self.window }
    }

    func top(limit: Int, now: Date) -> [Entry] {
        let minute = Int(now.timeIntervalSince1970 / 60)
        var sums: [String: Entry] = [:]
        for (key, bucket) in minutes where key > minute - Self.window {
            for (name, bytes) in bucket {
                var entry = sums[name] ?? Entry(name: name, download: 0, upload: 0)
                entry.download += bytes.down; entry.upload += bytes.up
                sums[name] = entry
            }
        }
        return Array(sums.values.filter { $0.total >= 1 }.sorted { $0.total > $1.total }.prefix(limit))
    }
}
