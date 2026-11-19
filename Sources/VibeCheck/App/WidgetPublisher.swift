import Foundation
import VibeCheckShared
import WidgetKit

/// Feeds the desktop widgets: once a minute (and right away when the vibe changes) it writes a small
/// snapshot into the app group container, but only while at least one VibeCheck widget is placed.
/// WidgetKit is asked to redraw only when the vibe changes, at most every 5 minutes; otherwise the widgets
/// re-read the snapshot on their own 15-minute timeline.
@MainActor
final class WidgetPublisher {
    static let shared = WidgetPublisher()

    var writeInterval: TimeInterval = 60
    /// WidgetKit budgets reloads from a background app; a flapping vibe shouldn't use it up.
    var reloadInterval: TimeInterval = 300
    var configurationCheckInterval: TimeInterval = 600

    private var lastWrite = Date.distantPast
    private var lastReload = Date.distantPast
    private var lastConfigurationCheck = Date.distantPast
    private var lastVibe: Vibe?
    /// Unknown until WidgetKit answers; assume yes so a freshly placed widget gets data on launch.
    private var hasWidgets = true
    private var pendingReload = false

    func tick(stats: SystemStats, now: Date = Date()) {
        checkConfigurations(now: now)
        guard hasWidgets else { return }
        let vibe = stats.vibe.vibe
        let changed = lastVibe != nil && lastVibe != vibe
        if changed { pendingReload = true }
        if changed || lastVibe == nil || now.timeIntervalSince(lastWrite) >= writeInterval {
            lastVibe = vibe
            lastWrite = now
            WidgetShared.write(Self.snapshot(report: stats.vibe, cpu: stats.cpu.total, memory: stats.memory.usage,
                                             cpuHour: stats.history.points(.cpu, .hour),
                                             memoryHour: stats.history.points(.memory, .hour), now: now))
        }
        // A throttled reload stays pending and goes out once the interval has passed.
        if pendingReload, now.timeIntervalSince(lastReload) >= reloadInterval {
            pendingReload = false
            lastReload = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func checkConfigurations(now: Date) {
        guard now.timeIntervalSince(lastConfigurationCheck) >= configurationCheckInterval else { return }
        lastConfigurationCheck = now
        WidgetCenter.shared.getCurrentConfigurations { [weak self] result in
            let placed = (try? result.get()).map { !$0.isEmpty } ?? true
            Task { @MainActor in
                guard let self else { return }
                // A widget was just placed: give it data now instead of at the next vibe change.
                if placed, !self.hasWidgets { self.lastWrite = .distantPast; self.lastReload = .distantPast; self.lastVibe = nil; self.pendingReload = true }
                self.hasWidgets = placed
            }
        }
    }

    /// Pure: the snapshot for the given readings. History points older than an hour are dropped.
    nonisolated static func snapshot(report: VibeReport, cpu: Double, memory: Double, cpuHour: [HistoryPoint],
                                     memoryHour: [HistoryPoint], now: Date) -> WidgetSnapshot {
        let cutoff = now.timeIntervalSince1970 - 3_600
        func recent(_ points: [HistoryPoint]) -> [Double] {
            WidgetSnapshot.downsample(points.filter { $0.t >= cutoff }.map { min(max($0.v, 0), 1) })
        }
        return WidgetSnapshot(vibe: report.vibe.rawValue, vibeTitle: report.vibe.title, verdict: report.verdict,
                              cpu: cpu, memory: memory, cpuHour: recent(cpuHour), memoryHour: recent(memoryHour),
                              date: now)
    }
}
