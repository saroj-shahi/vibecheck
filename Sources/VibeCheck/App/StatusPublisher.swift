import Foundation
import VibeCheckShared

/// Writes `~/Library/Application Support/VibeCheck/status.json` for the bundled `vibecheck` command line tool.
/// On a meaningful change (rules in `StatusSnapshot.shouldWrite`), at most every 10 s, with a 5 min heartbeat.
/// It follows the tick, so it pauses with sleep or lock.
@MainActor
final class StatusPublisher {
    static let shared = StatusPublisher()

    var url = StatusSnapshot.defaultURL()
    private var last: StatusSnapshot?
    private var lastWrite: Date?

    func tick(stats: SystemStats, now: Date = Date()) {
        let snapshot = Self.snapshot(stats: stats, now: now)
        guard StatusSnapshot.shouldWrite(new: snapshot, last: last, lastWrite: lastWrite, now: now) else { return }
        last = snapshot
        lastWrite = now
        let url = url
        guard let data = try? snapshot.encoded() else { return }
        Task.detached(priority: .utility) { Self.write(data, to: url) }
    }

    /// The file lists app names, so it is private to the user: a folder we create is 0700 (an existing one is left
    /// alone) and the file is 0600 from the moment it exists (temp file in the same folder, then an atomic rename).
    nonisolated static func write(_ data: Data, to url: URL) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let temp = dir.appendingPathComponent(".status-\(UUID().uuidString).tmp")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { return }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.close()
            guard rename(temp.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            try? fm.removeItem(at: temp)
        }
    }

    private static func snapshot(stats: SystemStats, now: Date) -> StatusSnapshot {
        let window = max(1, Int((30 / max(stats.refreshInterval, 0.5)).rounded()))
        let recent = stats.cpuHistory.suffix(window)
        let cpu = recent.isEmpty ? stats.cpu.total : recent.reduce(0, +) / Double(recent.count)
        let tracks = stats.appMemoryTracks.values.compactMap { track in track.samples.last.map { (track, $0) } }
            .filter { now.timeIntervalSince($0.1.date) <= AppMemoryHistory.interval * 3 }
            .sorted { $0.1.footprint > $1.1.footprint }
            .prefix(5)
            .map { track, last -> StatusSnapshot.MemoryApp in
                let g = AppMemoryHistory.growth(track.samples, now: now)
                return .init(name: track.name, bytes: last.footprint, processes: last.processCount,
                             growthBytes: g?.bytes, growthMinutes: g?.minutes)
            }
        var topCPU: [StatusSnapshot.CPUApp]?
        if stats.processDemand > 0, !stats.processes.isEmpty {
            topCPU = stats.topApps(by: \.cpu, limit: 5).map { .init(name: $0.name, cpu: $0.cpu, processes: $0.processCount) }
        }
        let b = stats.battery
        return StatusSnapshot(
            updatedAt: now, pid: ProcessInfo.processInfo.processIdentifier,
            vibe: ["vibing", "mid", "cooked"][min(max(stats.vibe.vibe.rawValue, 0), 2)],
            verdict: stats.vibe.verdict, culprit: stats.vibe.culprit?.rawValue, cpu: cpu,
            memoryPressure: ["normal", "warning", "critical"][stats.memory.pressure == .normal ? 0 : stats.memory.pressure == .warning ? 1 : 2],
            swapUsedBytes: stats.memory.swapUsed, thermalState: thermalName(stats.thermalState),
            battery: b.present ? .init(percent: b.percent, onAC: b.onAC, minutesLeft: b.onAC ? nil : b.minutesRemaining) : nil,
            topMemory: Array(tracks), topCPU: topCPU, topCPUAt: topCPU == nil ? nil : now)
    }

    nonisolated static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "nominal"
        }
    }
}
