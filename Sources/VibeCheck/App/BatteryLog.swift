import Foundation
import Observation

struct BatteryLogPoint: Codable, Equatable, Sendable {
    var t: TimeInterval      // seconds since 1970
    var charge: Double       // 0...1
    var health: Double?      // max capacity / design capacity
    var charging: Bool
}

/// Battery charge and health sampled every 15 minutes (or on a 3% change) and kept for 90 days.
@Observable
@MainActor
final class BatteryLogStore {
    nonisolated static let retention: TimeInterval = 90 * 86_400
    nonisolated static let interval: TimeInterval = 15 * 60

    private(set) var points: [BatteryLogPoint] = []

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var lastSave = Date()

    nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VibeCheck/battery-log.json")
    }

    init(fileURL: URL = BatteryLogStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    func record(_ sample: BatterySample, at date: Date = Date()) {
        guard sample.present else { return }
        let now = date.timeIntervalSince1970
        let point = BatteryLogPoint(t: now, charge: sample.percent, health: sample.health, charging: sample.isCharging)
        guard Self.shouldRecord(point, after: points.last) else { return }
        points.append(point)
        points.removeAll { $0.t < now - Self.retention }
        if date.timeIntervalSince(lastSave) > 1_800 { save(at: date) }
    }

    nonisolated static func shouldRecord(_ point: BatteryLogPoint, after last: BatteryLogPoint?) -> Bool {
        guard let last else { return true }
        return point.t - last.t >= interval
            || (point.t - last.t >= 60 && abs(point.charge - last.charge) >= 0.03)
    }

    /// Points with a health reading, thinned to the last one of each day.
    nonisolated static func healthTrend(_ points: [BatteryLogPoint]) -> [(t: TimeInterval, health: Double)] {
        var byDay: [Int: (TimeInterval, Double)] = [:]
        for p in points {
            if let h = p.health { byDay[Int(p.t / 86_400)] = (p.t, h) }
        }
        return byDay.keys.sorted().compactMap { byDay[$0].map { (t: $0.0, health: $0.1) } }
    }

    func save(at date: Date = Date()) {
        lastSave = date
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(points).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("VibeCheck: could not save battery log: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([BatteryLogPoint].self, from: data) else { return }
        let now = Date().timeIntervalSince1970
        points = saved.filter { $0.t >= now - Self.retention }
    }
}
