import Foundation

enum Fmt {
    private static let units = ["B", "KB", "MB", "GB", "TB"]

    static func bytes(_ value: Double) -> String {
        var v = max(0, value)
        var i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        let decimals = (i == 0 || v >= 100) ? 0 : 1
        return String(format: "%.\(decimals)f %@", v, units[i])
    }

    static func rate(_ value: Double) -> String { bytes(value) + "/s" }

    /// Token counts: "840", "12K", "1.2M", "412M", "1.3B".
    static func tokens(_ value: Int) -> String {
        let v = Double(max(0, value))
        for (limit, suffix) in [(1e9, "B"), (1e6, "M"), (1e3, "K")] where v >= limit {
            let scaled = v / limit
            return scaled < 10 ? String(format: "%.1f%@", scaled, suffix) : String(format: "%.0f%@", scaled, suffix)
        }
        return String(Int(v))
    }

    /// Short form for the menu bar, e.g. "1.2M", "340K", "0K".
    static func compactRate(_ value: Double) -> String {
        let kb = max(0, value) / 1024
        if kb < 1000 { return String(format: "%.0fK", kb) }
        let mb = kb / 1024
        if mb < 100 { return String(format: "%.1fM", mb) }
        if mb < 1000 { return String(format: "%.0fM", mb) }
        return String(format: "%.1fG", mb / 1024)
    }

    /// Short sizes for the menu bar: "512M", "12.3G", "1.2T".
    static func compactBytes(_ value: Double) -> String {
        let gb = max(0, value) / 1_073_741_824
        if gb < 1 { return String(format: "%.0fM", gb * 1024) }
        if gb < 100 { return String(format: "%.1fG", gb) }
        if gb < 1000 { return String(format: "%.0fG", gb) }
        return String(format: "%.1fT", gb / 1024)
    }

    /// "3:25" for minutes left, as the menu bar battery shows it.
    static func clockDuration(_ minutes: Int) -> String {
        String(format: "%d:%02d", max(0, minutes) / 60, max(0, minutes) % 60)
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", max(0, fraction) * 100)
    }

    static func minutes(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400, hours = (total % 86_400) / 3600, mins = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}

extension String {
    /// A C string from a fixed-size buffer filled by a system call (stops at the first NUL).
    init(cBuffer buffer: [CChar]) {
        self = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
