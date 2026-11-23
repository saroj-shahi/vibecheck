import AppKit
import Darwin
import Observation

/// One process's cumulative energy at one scan, already tied to the app macOS holds responsible for it.
struct EnergyScanItem: Sendable, Equatable {
    let pid: Int32
    let owner: Int32        // responsible pid
    let ownerName: String   // proc_name fallback for the owner
    let nanojoules: UInt64
    let start: UInt64       // ri_proc_start_abstime: a reused pid has a different start
}

/// Energy used per app per local calendar day ("Top battery drainers today").
/// Sampled at most once a minute with libproc (no `ps`), kept for today and yesterday only,
/// and saved to `Application Support/VibeCheck/energy.json` (at most every 5 minutes, and on quit).
@MainActor @Observable
final class EnergyLog {
    struct Entry: Codable, Equatable, Sendable {
        var name: String
        var joules: Double
    }

    struct Row: Identifiable, Equatable {
        let name: String
        let joules: Double
        let share: Double
        var id: String { name }
        var wattHours: Double { joules / 3600 }
    }

    enum Day { case today, yesterday }

    nonisolated static let interval: TimeInterval = 60
    nonisolated static let saveInterval: TimeInterval = 300

    /// "yyyy-MM-dd" (local) -> app name -> energy.
    private(set) var days: [String: [String: Entry]] = [:]

    @ObservationIgnored private var previous: [Int32: (nj: UInt64, start: UInt64)] = [:]
    @ObservationIgnored private var lastSample: Date?
    @ObservationIgnored private var lastSave = Date()
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var scanning = false
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let calendar: Calendar

    nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VibeCheck/energy.json")
    }

    init(fileURL: URL = EnergyLog.defaultFileURL, calendar: Calendar = .current, now: Date = Date(),
         savesOnQuit: Bool = false) {
        self.fileURL = fileURL
        self.calendar = calendar
        load(now: now)
        if savesOnQuit {
            // No hook in the app delegate for this log: save when the app terminates.
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                                   queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.save() }
            }
        }
    }

    // MARK: Days

    nonisolated static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    nonisolated static func key(_ day: Day, now: Date, calendar: Calendar) -> String {
        switch day {
        case .today: dayKey(now, calendar: calendar)
        case .yesterday: dayKey(calendar.date(byAdding: .day, value: -1, to: now) ?? now, calendar: calendar)
        }
    }

    // MARK: Recording

    func isDue(now: Date = Date()) -> Bool {
        lastSample.map { now.timeIntervalSince($0) >= Self.interval - 0.5 } ?? true
    }

    /// Kicks off a scan when one is due; the libproc work runs off the main thread.
    func sampleIfDue(now: Date = Date()) {
        guard !scanning, isDue(now: now) else { return }
        scanning = true
        Task.detached(priority: .utility) {
            let items = EnergyLog.scan()
            await MainActor.run {
                self.record(items, now: Date(), resolveName: { owner, fallback in
                    NSRunningApplication(processIdentifier: owner)?.localizedName ?? fallback
                })
                self.scanning = false
            }
        }
    }

    /// Adds each process's energy since its last reading to its app's total for the current day.
    /// A pid seen for the first time, or reused by a different process, only sets a baseline.
    func record(_ items: [EnergyScanItem], now: Date = Date(),
                resolveName: (_ owner: Int32, _ fallback: String) -> String = { $1 }) {
        lastSample = now
        let today = Self.dayKey(now, calendar: calendar)
        var deltas: [Int32: (joules: Double, fallback: String)] = [:]
        var next: [Int32: (nj: UInt64, start: UInt64)] = [:]
        next.reserveCapacity(items.count)
        for item in items {
            next[item.pid] = (item.nanojoules, item.start)
            guard let old = previous[item.pid], old.start == item.start, item.nanojoules >= old.nj else { continue }
            let joules = Double(item.nanojoules - old.nj) / 1e9
            guard joules > 0 else { continue }
            let entry = deltas[item.owner] ?? (0, item.ownerName)
            deltas[item.owner] = (entry.joules + joules, entry.fallback)
        }
        previous = next

        if !deltas.isEmpty {
            var day = days[today] ?? [:]
            for (owner, delta) in deltas {
                let name = resolveName(owner, delta.fallback)
                guard !name.isEmpty else { continue }
                var entry = day[name] ?? Entry(name: name, joules: 0)
                entry.joules += delta.joules
                day[name] = entry
            }
            days[today] = day
            dirty = true
        }
        // Only today and yesterday are kept.
        let keep: Set = [today, Self.key(.yesterday, now: now, calendar: calendar)]
        if days.keys.contains(where: { !keep.contains($0) }) {
            days = days.filter { keep.contains($0.key) }
            dirty = true
        }
        if dirty, now.timeIntervalSince(lastSave) >= Self.saveInterval { save(at: now) }
    }

    // MARK: Reading

    /// Total joules for the day and its top apps by energy, each with its share of that total.
    func leaderboard(_ day: Day, limit: Int = 5, now: Date = Date()) -> (total: Double, rows: [Row]) {
        let entries = Array((days[Self.key(day, now: now, calendar: calendar)] ?? [:]).values)
        let total = entries.reduce(0) { $0 + $1.joules }
        guard total > 0 else { return (0, []) }
        let rows = entries.sorted { $0.joules != $1.joules ? $0.joules > $1.joules : $0.name < $1.name }
            .prefix(limit).map { Row(name: $0.name, joules: $0.joules, share: $0.joules / total) }
        return (total, Array(rows))
    }

    /// "1.4 Wh", or "<0.1 Wh" for tiny amounts.
    nonisolated static func label(wattHours: Double) -> String {
        wattHours < 0.05 ? "<0.1 Wh" : String(format: "%.1f Wh", wattHours)
    }

    // MARK: Scanning

    /// Walks every process with libproc; processes that can't be read are skipped.
    nonisolated static func scan() -> [EnergyScanItem] {
        let capacity = Int(proc_listallpids(nil, 0))
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity + 64)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return [] }
        let readings = EnergySampler.read(pids: pids.prefix(count).filter { $0 > 0 })
        var names: [Int32: String] = [:]
        var items: [EnergyScanItem] = []
        items.reserveCapacity(readings.count)
        for (pid, reading) in readings {
            let owner = ProcessSampler.responsible(for: pid)
            let name = names[owner] ?? EnergySampler.processName(owner) ?? "pid \(owner)"
            names[owner] = name
            items.append(EnergyScanItem(pid: pid, owner: owner, ownerName: name,
                                        nanojoules: reading.nanojoules, start: reading.start))
        }
        return items
    }

    // MARK: Persistence

    private struct File: Codable {
        var version = 1
        var days: [String: [String: Entry]]
    }

    private func load(now: Date) {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return }
        let keep: Set = [Self.dayKey(now, calendar: calendar), Self.key(.yesterday, now: now, calendar: calendar)]
        days = file.days.filter { keep.contains($0.key) }
    }

    func save(at date: Date = Date()) {
        lastSave = date
        guard dirty else { return }
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(File(days: days)) else { return }
        // Atomic, so a crash mid-write can't leave a truncated file that loses both days on the next launch.
        do {
            try data.write(to: fileURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            dirty = false
        } catch {}
    }
}
