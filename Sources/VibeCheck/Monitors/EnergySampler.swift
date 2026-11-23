import Darwin
import Foundation

/// Per-process energy from `proc_pid_rusage`. Uses `ri_energy_nj` (RUSAGE_INFO_V6): cumulative
/// nanojoules the process has used, as macOS counts it. Watts come from the difference between two readings.
enum EnergySampler {
    struct Reading: Equatable, Sendable {
        let nanojoules: UInt64
        /// `ri_proc_start_abstime`: tells a reused pid from the process we saw before.
        let start: UInt64
        /// Monotonic seconds when the reading was taken.
        let time: TimeInterval
    }

    /// Shortest gap between two readings that gives a steady number.
    nonisolated static let minimumInterval: TimeInterval = 1

    /// Watts between two readings, or nil when there's nothing honest to say: no earlier reading,
    /// a different process (pid reused), a counter that went backwards, or under a second apart.
    nonisolated static func watts(previous: Reading?, current: Reading) -> Double? {
        guard let previous, previous.start == current.start,
              current.nanojoules >= previous.nanojoules else { return nil }
        let seconds = current.time - previous.time
        guard seconds >= minimumInterval else { return nil }
        return Double(current.nanojoules - previous.nanojoules) / seconds / 1e9
    }

    /// Reads the cumulative energy of each pid; pids that can't be read (gone, not ours) are left out.
    nonisolated static func read(pids: [Int32]) -> [Int32: Reading] {
        let now = ProcessInfo.processInfo.systemUptime
        var result: [Int32: Reading] = [:]
        result.reserveCapacity(pids.count)
        for pid in pids {
            var info = rusage_info_v6()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            }
            guard status == 0 else { continue }
            result[pid] = Reading(nanojoules: info.ri_energy_nj, start: info.ri_proc_start_abstime, time: now)
        }
        return result
    }

    /// Watts for every pid with a usable pair of readings.
    nonisolated static func watts(previous: [Int32: Reading], current: [Int32: Reading]) -> [Int32: Double] {
        var result: [Int32: Double] = [:]
        for (pid, reading) in current {
            if let value = watts(previous: previous[pid], current: reading) { result[pid] = value }
        }
        return result
    }

    /// "~1.2 W" under 10 W, "~12 W" above; nil under 0.1 W (not worth a column).
    nonisolated static func label(_ watts: Double?) -> String? {
        guard let watts, watts >= 0.1 else { return nil }
        return watts < 9.95 ? String(format: "~%.1f W", watts) : String(format: "~%.0f W", watts)
    }
}
