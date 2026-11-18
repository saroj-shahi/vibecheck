import Darwin
import Foundation
import SystemConfiguration

struct NetworkSample {
    var download: Double = 0     // bytes per second
    var upload: Double = 0
    var totalDownloaded: UInt64 = 0 // since boot, all non-loopback interfaces
    var totalUploaded: UInt64 = 0
    var interface: String?
    var ipv4: String?
}

final class NetworkMonitor {
    private var lastIn: UInt64 = 0
    private var lastOut: UInt64 = 0
    private var lastTime: Date?

    func sample() -> NetworkSample {
        let (bytesIn, bytesOut) = Self.interfaceCounters()
        let now = Date()
        var result = NetworkSample(totalDownloaded: bytesIn, totalUploaded: bytesOut)

        if let lastTime, bytesIn >= lastIn, bytesOut >= lastOut {
            let elapsed = max(now.timeIntervalSince(lastTime), 0.001)
            result.download = Double(bytesIn - lastIn) / elapsed
            result.upload = Double(bytesOut - lastOut) / elapsed
        }
        lastIn = bytesIn; lastOut = bytesOut; lastTime = now

        result.interface = Self.primaryInterface()
        if let name = result.interface { result.ipv4 = Self.ipv4Address(for: name) }
        return result
    }

    /// 64-bit byte counters via NET_RT_IFLIST2 (getifaddrs only exposes 32-bit counters that wrap at 4 GB).
    private static func interfaceCounters() -> (UInt64, UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return (0, 0) }

        var totalIn: UInt64 = 0, totalOut: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let msg = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if msg.ifm_flags & IFF_LOOPBACK == 0 {
                        totalIn &+= msg.ifm_data.ifi_ibytes
                        totalOut &+= msg.ifm_data.ifi_obytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return (totalIn, totalOut)
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
                return String(cString: host)
            }
        }
        return nil
    }
}
