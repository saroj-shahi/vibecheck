import AppKit
import Darwin

/// One app's memory (all processes macOS holds responsible to it) at one scan.
struct AppMemoryGroup: Sendable {
    let pid: Int32          // responsible pid
    let startTime: Int64    // that pid's start time (seconds), so a reused pid is a different app
    let name: String        // proc_name fallback
    let footprint: Double
    let processCount: Int
}

struct AppMemorySample: Sendable {
    let date: Date
    let footprint: Double
    let processCount: Int
}

/// Identity of an app across scans.
struct AppMemoryKey: Hashable, Sendable {
    let pid: Int32
    let startTime: Int64
}

struct AppMemoryTrack: Sendable {
    var name: String
    var samples: [AppMemorySample]
}

/// Per-app memory over about an hour, sampled with libproc once a minute (no child processes).
/// Powers the verdict line "Chrome grew 2.4 GB in the last hour".
struct AppMemoryHistory: Sendable {
    static let interval: TimeInterval = 60
    static let window: TimeInterval = 65 * 60
    static let minHistory: TimeInterval = 20 * 60
    static let maxTracked = 15

    private(set) var tracks: [AppMemoryKey: AppMemoryTrack] = [:]
    private(set) var lastScan: Date?

    func isDue(now: Date = Date()) -> Bool {
        lastScan.map { now.timeIntervalSince($0) >= Self.interval - 0.5 } ?? true
    }

    /// Records a scan: the top 15 by footprint plus tracked apps still alive; the rest are dropped.
    mutating func record(_ groups: [AppMemoryGroup], now: Date = Date(), resolveName: (AppMemoryGroup) -> String = { $0.name }) {
        // After a pause (sleep, lock) growth would span time nobody was using the Mac: start over.
        if let lastScan, now.timeIntervalSince(lastScan) > Self.interval * 3 { tracks.removeAll() }
        lastScan = now
        let alive = Dictionary(groups.map { (AppMemoryKey(pid: $0.pid, startTime: $0.startTime), $0) }, uniquingKeysWith: { a, _ in a })
        var next: [AppMemoryKey: AppMemoryTrack] = [:]
        let chosen = Set(Self.topByFootprint(groups, limit: Self.maxTracked).map { AppMemoryKey(pid: $0.pid, startTime: $0.startTime) })
        for (key, group) in alive where chosen.contains(key) || tracks[key] != nil {
            var track = tracks[key] ?? AppMemoryTrack(name: resolveName(group), samples: [])
            track.samples.append(AppMemorySample(date: now, footprint: group.footprint, processCount: group.processCount))
            track.samples.removeAll { now.timeIntervalSince($0.date) > Self.window }
            next[key] = track
        }
        tracks = next
    }

    nonisolated static func topByFootprint(_ groups: [AppMemoryGroup], limit: Int) -> [AppMemoryGroup] {
        Array(groups.sorted { $0.footprint > $1.footprint }.prefix(limit))
    }

    /// The app using the most memory now, with its growth over about the last hour.
    func top(now: Date = Date()) -> (name: String, footprint: Double, processCount: Int, growth: Double?, minutes: Int?)? {
        let current = tracks.values.compactMap { track in track.samples.last.map { (track, $0) } }
            .filter { now.timeIntervalSince($0.1.date) <= Self.interval * 3 }
            .max { $0.1.footprint < $1.1.footprint }
        guard let (track, last) = current else { return nil }
        let g = Self.growth(track.samples, now: now)
        return (track.name, last.footprint, last.processCount, g?.bytes, g?.minutes)
    }

    /// Bytes gained since the sample closest to an hour ago, and the actual span in minutes.
    /// Nil with under 20 minutes of history; negative bytes mean it shrank (callers make no growth claim).
    nonisolated static func growth(_ samples: [AppMemorySample], now: Date) -> (bytes: Double, minutes: Int)? {
        guard let last = samples.last else { return nil }
        let past = samples.dropLast()
        guard let base = past.min(by: {
            abs(now.timeIntervalSince($0.date) - 3600) < abs(now.timeIntervalSince($1.date) - 3600)
        }) else { return nil }
        let span = last.date.timeIntervalSince(base.date)
        guard span >= minHistory else { return nil }
        return (last.footprint - base.footprint, Int((span / 60).rounded()))
    }

    // MARK: Scanning

    /// Walks every process with libproc. Processes that can't be read (other users) are skipped.
    nonisolated static func scan() -> [AppMemoryGroup] {
        let capacity = Int(proc_listallpids(nil, 0))
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity + 64)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return [] }

        var footprints: [Int32: (bytes: Double, count: Int)] = [:]
        for pid in pids.prefix(count) where pid > 0 {
            guard let bytes = footprint(of: pid) else { continue }
            let owner = ProcessSampler.responsible(for: pid)
            let entry = footprints[owner] ?? (0, 0)
            footprints[owner] = (entry.bytes + bytes, entry.count + 1)
        }
        return footprints.compactMap { owner, entry in
            guard let start = startTime(of: owner) else { return nil }
            return AppMemoryGroup(pid: owner, startTime: start, name: procName(owner) ?? "pid \(owner)",
                                  footprint: entry.bytes, processCount: entry.count)
        }
    }

    nonisolated private static func footprint(of pid: pid_t) -> Double? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        return result == 0 ? Double(info.ri_phys_footprint) : nil
    }

    nonisolated private static func startTime(of pid: pid_t) -> Int64? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Int64(info.pbi_start_tvsec)
    }

    nonisolated private static func procName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Display name: the app's own name when it is a running app, else the process name.
    @MainActor static func displayName(_ group: AppMemoryGroup) -> String {
        NSRunningApplication(processIdentifier: group.pid)?.localizedName ?? group.name
    }
}
