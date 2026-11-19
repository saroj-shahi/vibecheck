import Darwin
import Foundation
import SystemConfiguration

struct InterfaceUsage: Identifiable {
    var id: String { bsdName }
    let bsdName: String        // "en0"
    let displayName: String    // "Wi-Fi"
    var download: Double = 0
    var upload: Double = 0
    let totalIn: UInt64
    let totalOut: UInt64
    var isActive: Bool { max(download, upload) >= 2048 }
}

struct NetworkSample {
    var download: Double = 0     // bytes per second
    var upload: Double = 0
    var totalDownloaded: UInt64 = 0 // since boot, all non-loopback interfaces
    var totalUploaded: UInt64 = 0
    var interface: String?
    var ipv4: String?
    /// Every interface that has carried traffic since boot, busiest first.
    var interfaces: [InterfaceUsage] = []
}

final class NetworkMonitor {
    private var lastIn: UInt64 = 0
    private var lastOut: UInt64 = 0
    private var lastTime: Date?
    private var lastPerInterface: [String: (UInt64, UInt64)] = [:]
    private var displayNames: [String: String] = [:]
    private var displayNamesLoaded: Date?

    func sample() -> NetworkSample {
        let counters = Self.interfaceCounters()
        let bytesIn = counters.values.reduce(UInt64(0)) { $0 &+ $1.0 }
        let bytesOut = counters.values.reduce(UInt64(0)) { $0 &+ $1.1 }
        let now = Date()
        var result = NetworkSample(totalDownloaded: bytesIn, totalUploaded: bytesOut)
        let elapsed = lastTime.map { max(now.timeIntervalSince($0), 0.001) }

        if let elapsed, bytesIn >= lastIn, bytesOut >= lastOut {
            result.download = Double(bytesIn - lastIn) / elapsed
            result.upload = Double(bytesOut - lastOut) / elapsed
        }

        refreshDisplayNamesIfNeeded(now)
        result.interfaces = counters.compactMap { name, totals -> InterfaceUsage? in
            guard totals.0 > 0 || totals.1 > 0 else { return nil }
            var usage = InterfaceUsage(bsdName: name, displayName: displayNames[name] ?? Self.fallbackName(name),
                                       totalIn: totals.0, totalOut: totals.1)
            if let elapsed, let previous = lastPerInterface[name], totals.0 >= previous.0, totals.1 >= previous.1 {
                usage.download = Double(totals.0 - previous.0) / elapsed
                usage.upload = Double(totals.1 - previous.1) / elapsed
            }
            return usage
        }
        .sorted { ($0.totalIn &+ $0.totalOut) > ($1.totalIn &+ $1.totalOut) }

        lastIn = bytesIn; lastOut = bytesOut; lastTime = now
        lastPerInterface = counters

        result.interface = Self.primaryInterface()
        if let name = result.interface { result.ipv4 = Self.ipv4Address(for: name) }
        return result
    }

    /// Friendly names ("Wi-Fi", "Thunderbolt Ethernet") from System Configuration; refreshed every few minutes.
    private func refreshDisplayNamesIfNeeded(_ now: Date) {
        if let loaded = displayNamesLoaded, now.timeIntervalSince(loaded) < 300 { return }
        displayNamesLoaded = now
        let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        for interface in all {
            if let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
               let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
                displayNames[bsd] = name
            }
        }
    }

    static func fallbackName(_ bsd: String) -> String {
        switch bsd {
        case let n where n.hasPrefix("utun"): "VPN / tunnel (\(n))"
        case let n where n.hasPrefix(String(localized: "awdl")): String(localized: "AirDrop (\(n))")
        case let n where n.hasPrefix(String(localized: "llw")): String(localized: "Low-latency Wi-Fi (\(n))")
        case let n where n.hasPrefix(String(localized: "bridge")): String(localized: "Bridge (\(n))")
        case let n where n.hasPrefix(String(localized: "anpi")): String(localized: "Internal link (\(n))")
        default: bsd
        }
    }

    /// Per-interface 64-bit byte counters via NET_RT_IFLIST2 (getifaddrs only exposes 32-bit counters
    /// that wrap at 4 GB). Loopback is excluded.
    private static func interfaceCounters() -> [String: (UInt64, UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [:] }

        var result: [String: (UInt64, UInt64)] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let msg = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if msg.ifm_flags & IFF_LOOPBACK == 0,
                       if_indextoname(UInt32(msg.ifm_index), &nameBuffer) != nil {
                        result[String(cBuffer: nameBuffer)] = (msg.ifm_data.ifi_ibytes, msg.ifm_data.ifi_obytes)
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return result
    }

    private static func primaryInterface() -> String? {
        guard let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return global["PrimaryInterface"] as? String
    }

    private static func ipv4Address(for interface: String) -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: entry.pointee.ifa_name) == interface else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                return String(cBuffer: host)
            }
        }
        return nil
    }
}
