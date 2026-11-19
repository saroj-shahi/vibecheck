import Foundation
import Observation

enum HistoryKey: String, Codable, CaseIterable {
    case cpu, cpuSystem, gpu, memory, temperature, download, upload, read, write, battery
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case live, hour, day

    var id: String { rawValue }
    var label: String {
        switch self {
        case .live: "Live"
        case .hour: "1H"
        case .day: "24H"
        }
    }
    /// Each stored point is the average of all samples in one bucket of this length.
    var bucket: TimeInterval { self == .day ? 144 : 6 }
    var span: TimeInterval { self == .day ? 86_400 : 3_600 }

    static let stored: [HistoryRange] = [.hour, .day]
}

struct HistoryPoint: Codable {
    var t: TimeInterval   // bucket start, seconds since 1970
    var v: Double
}

/// Long-range history: 6-second averages for the last hour and 144-second averages for the last day,
/// saved to Application Support so graphs survive restarts. Gaps (sleep, app not running) stay gaps.
@Observable
@MainActor
final class HistoryStore {
    private(set) var series: [String: [HistoryPoint]] = [:]

    @ObservationIgnored private var accumulators: [String: (start: TimeInterval, sum: Double, count: Int)] = [:]
    @ObservationIgnored private var lastSave = Date()

    @ObservationIgnored private let fileURL: URL

    nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VibeCheck/history.json")
    }

    init(fileURL: URL = HistoryStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    private static func id(_ range: HistoryRange, _ key: HistoryKey) -> String { "\(range.rawValue).\(key.rawValue)" }

    func points(_ key: HistoryKey, _ range: HistoryRange) -> [HistoryPoint] {
        series[Self.id(range, key)] ?? []
    }

    func record(_ values: [HistoryKey: Double], at date: Date = Date()) {
        let now = date.timeIntervalSince1970
        for range in HistoryRange.stored {
            let bucketStart = (now / range.bucket).rounded(.down) * range.bucket
            for (key, value) in values where value.isFinite {
                let id = Self.id(range, key)
                if let acc = accumulators[id], acc.start != bucketStart {
                    flush(id, acc, range: range, now: now)
                    accumulators[id] = nil
                }
                var acc = accumulators[id] ?? (bucketStart, 0, 0)
                acc.sum += value
                acc.count += 1
                accumulators[id] = acc
            }
        }
        if date.timeIntervalSince(lastSave) > 300 { save(at: date) }
    }

    private func flush(_ id: String, _ acc: (start: TimeInterval, sum: Double, count: Int),
                       range: HistoryRange, now: TimeInterval) {
        guard acc.count > 0 else { return }
        var points = series[id] ?? []
        points.append(HistoryPoint(t: acc.start, v: acc.sum / Double(acc.count)))
        let cutoff = now - range.span
        if let firstKept = points.firstIndex(where: { $0.t >= cutoff }), firstKept > 0 {
            points.removeFirst(firstKept)
        }
        series[id] = points
    }

    func save(at date: Date = Date()) {
        lastSave = date
        do {
            let url = fileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(series).write(to: url, options: .atomic)
        } catch {
            NSLog("VibeCheck: could not save history: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([String: [HistoryPoint]].self, from: data) else { return }
        let now = Date().timeIntervalSince1970
        series = saved.reduce(into: [:]) { result, entry in
            let span = entry.key.hasPrefix("day.") ? HistoryRange.day.span : HistoryRange.hour.span
            result[entry.key] = entry.value.filter { $0.t >= now - span }
        }
    }
}
