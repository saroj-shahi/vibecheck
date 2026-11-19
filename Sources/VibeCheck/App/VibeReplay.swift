import Foundation
import Observation

/// One stretch of the Mac being mid or cooked.
struct VibeEpisode: Codable, Equatable, Sendable {
    var start: TimeInterval          // seconds since 1970
    var end: TimeInterval
    var worst: Int                   // Vibe.rawValue of the worst level reached
    var culprit: String?             // Module.rawValue behind the verdict
    var process: String?             // loudest app, when it was known

    var level: Vibe { Vibe(rawValue: worst) ?? .mid }
}

/// Records mid / cooked episodes for 30 days so the deck can replay how the day went.
@Observable
@MainActor
final class VibeReplayStore {
    nonisolated static let retention: TimeInterval = 30 * 86_400

    private(set) var episodes: [VibeEpisode] = []
    /// The episode in progress (not saved until it ends).
    private(set) var open: VibeEpisode?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var lastSave = Date()

    nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VibeCheck/vibe-episodes.json")
    }

    init(fileURL: URL = VibeReplayStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    /// Call once per tick with the current (debounced) level.
    func observe(level: Vibe, culprit: Module?, process: String?, at date: Date = Date()) {
        let now = date.timeIntervalSince1970
        if level == .vibing {
            if let finished = open {
                var done = finished
                done.end = now
                episodes.append(done)
                open = nil
                trim(now: now)
                save(at: date)
            }
            return
        }
        if var current = open {
            current.end = now
            if level.rawValue > current.worst {
                current.worst = level.rawValue
                if let culprit { current.culprit = culprit.rawValue }
            }
            if current.culprit == nil, let culprit { current.culprit = culprit.rawValue }
            if let process, current.process == nil || level.rawValue >= current.worst { current.process = process }
            open = current
        } else {
            open = VibeEpisode(start: now, end: now, worst: level.rawValue,
                               culprit: culprit?.rawValue, process: process)
        }
        if date.timeIntervalSince(lastSave) > 300 { save(at: date) }
    }

    /// Saved episodes plus the one in progress.
    var all: [VibeEpisode] { episodes + (open.map { [$0] } ?? []) }

    private func trim(now: TimeInterval) {
        episodes.removeAll { $0.end < now - Self.retention }
    }

    func save(at date: Date = Date()) {
        lastSave = date
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(all).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("VibeCheck: could not save vibe episodes: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([VibeEpisode].self, from: data) else { return }
        let now = Date().timeIntervalSince1970
        episodes = saved.filter { $0.end >= now - Self.retention }
    }

    // MARK: Pure helpers

    /// "Chrome Helper cooked your Mac 4 times this week", or a calmer line when nothing was cooked.
    nonisolated static func weeklySummary(_ episodes: [VibeEpisode], now: Date = Date()) -> String {
        let since = now.timeIntervalSince1970 - 7 * 86_400
        let week = episodes.filter { $0.end >= since }
        func times(_ n: Int) -> String { n == 1 ? String(localized: "once") : n == 2 ? String(localized: "twice") : String(localized: "\(n) times") }

        func top(_ list: [VibeEpisode]) -> (name: String, count: Int)? {
            var counts: [String: Int] = [:]
            for e in list {
                let name = e.process ?? e.culprit.flatMap { Module(rawValue: $0)?.title }
                if let name { counts[name, default: 0] += 1 }
            }
            return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }.map { ($0.key, $0.value) }
        }

        let cooked = week.filter { $0.level == .cooked }
        if let t = top(cooked) { return String(localized: "\(t.name) cooked your Mac \(times(t.count)) this week.") }
        if !cooked.isEmpty { return String(localized: "Your Mac got cooked \(times(cooked.count)) this week.") }
        if let t = top(week) { return String(localized: "\(t.name) made your Mac mid \(times(t.count)) this week.") }
        if !week.isEmpty { return String(localized: "Your Mac was mid \(times(week.count)) this week.") }
        return String(localized: "Your Mac has been vibing all week.")
    }

    /// Colored stretches of the last `span` seconds; anything not covered by an episode is vibing.
    nonisolated static func segments(_ episodes: [VibeEpisode], now: Date = Date(),
                                     span: TimeInterval = 86_400) -> [(start: Double, end: Double, vibe: Vibe)] {
        let t1 = now.timeIntervalSince1970
        let t0 = t1 - span
        var out: [(Double, Double, Vibe)] = []
        var cursor = t0
        for e in episodes.sorted(by: { $0.start < $1.start }) where e.end > t0 && e.start < t1 {
            let s = max(e.start, t0, cursor)
            let f = min(max(e.end, e.start + 60), t1)   // at least a visible sliver
            guard f > s else { continue }
            if s > cursor { out.append((cursor, s, .vibing)) }
            out.append((s, f, e.level))
            cursor = f
        }
        if cursor < t1 { out.append((cursor, t1, .vibing)) }
        return out.map { (start: ($0.0 - t0) / span, end: ($0.1 - t0) / span, vibe: $0.2) }
    }
}
