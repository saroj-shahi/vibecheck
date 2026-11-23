import AppKit
import Observation
import SwiftUI

/// Notices when a long sleep on battery cost a lot of charge, finds out what woke the Mac, and keeps one
/// small report for the deck home to show once. Wake causes come from one `pmset -g log` run in the
/// background, only when a report is being built.
@MainActor
@Observable
final class SleepDrain {
    static let shared = SleepDrain()

    struct WakeSummary: Equatable, Codable {
        var wakes = 0
        /// Plain-word cause → count.
        var causes: [String: Int] = [:]

        /// Most common named cause, ignoring "other". Nil when nothing is named.
        var topCause: (name: String, count: Int)? {
            causes.filter { $0.key != "other" }
                .max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }
                .map { ($0.key, $0.value) }
        }
    }

    struct Report: Equatable, Codable {
        var drop: Int            // percentage points
        var hours: Int
        var summary: WakeSummary
        var created: Date
    }

    struct Mark: Equatable, Codable {
        var percent: Double      // 0...1
        var onBattery: Bool
        var date: Date
    }

    nonisolated static let minSleep: TimeInterval = 2 * 3600
    nonisolated static let minDrop = 5
    nonisolated static let expiry: TimeInterval = 12 * 3600
    private nonisolated static let reportKey = "sleepDrainReport"

    /// The report waiting to be shown, if it hasn't expired.
    private(set) var report: Report?

    private var sleepMark: Mark?
    private var started = false
    private let defaults = UserDefaults.standard

    func start() {
        guard !started else { return }
        started = true
        report = Self.load(defaults: defaults, now: Date())
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.willSleep() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        }
    }

    func dismiss() {
        report = nil
        defaults.removeObject(forKey: Self.reportKey)
    }

    /// Drops an expired report; called when the deck opens.
    func refresh() {
        if let r = report, Self.isExpired(r, now: Date()) { dismiss() }
    }

    private static func mark() -> Mark? {
        let s = BatteryMonitor.sample()
        guard s.present else { return nil }
        return Mark(percent: s.percent, onBattery: !s.onAC, date: Date())
    }

    /// Keeps the first mark of a sleep: a dark wake doesn't fire didWake, so a second willSleep must not replace it.
    nonisolated static func keepFirst(_ existing: Mark?, _ fresh: () -> Mark?) -> Mark? { existing ?? fresh() }

    private func willSleep() { sleepMark = Self.keepFirst(sleepMark, Self.mark) }

    private func didWake() {
        defer { sleepMark = nil }
        guard let start = sleepMark, let end = Self.mark() else { return }
        guard let drain = Self.evaluate(start: start, end: end) else { return }
        // Wake entries land a moment before the notification; keep our own wake out of the count.
        let to = end.date.addingTimeInterval(-5)
        Task.detached {
            let log = Self.runPmset()
            let summary = log.map { Self.parse(log: $0, from: start.date, to: to) } ?? WakeSummary()
            await MainActor.run {
                let r = Report(drop: drain.drop, hours: drain.hours, summary: summary, created: Date())
                self.report = r
                if let data = try? JSONEncoder().encode(r) { self.defaults.set(data, forKey: Self.reportKey) }
            }
        }
    }

    // MARK: Pure helpers

    /// Drop and whole hours if this sleep counts as a drain, else nil.
    nonisolated static func evaluate(start: Mark, end: Mark) -> (drop: Int, hours: Int)? {
        let length = end.date.timeIntervalSince(start.date)
        guard length >= minSleep, start.onBattery, end.onBattery else { return nil }
        let drop = Int(((start.percent - end.percent) * 100).rounded())
        guard drop >= minDrop else { return nil }
        return (drop, Int((length / 3600).rounded()))
    }

    nonisolated static func isExpired(_ r: Report, now: Date) -> Bool {
        now.timeIntervalSince(r.created) > expiry || r.created > now.addingTimeInterval(60)
    }

    nonisolated static func load(defaults: UserDefaults, now: Date) -> Report? {
        guard let data = defaults.data(forKey: reportKey) else { return nil }
        guard let r = try? JSONDecoder().decode(Report.self, from: data), !isExpired(r, now: now) else {
            defaults.removeObject(forKey: reportKey)
            return nil
        }
        return r
    }

    /// The one calm line for the deck.
    nonisolated static func text(for r: Report) -> String {
        var s = String(localized: "Overnight: battery dropped \(r.drop)% in \(r.hours) h.")
        if r.summary.wakes > 0 {
            s += " " + String(localized: "It woke \(r.summary.wakes) times")
            if let top = r.summary.topCause {
                let word = top.count * 2 >= r.summary.wakes ? String(localized: "mostly") : String(localized: "most often")
                s += String(localized: ", \(word) for \(top.name).")
            } else {
                s += "."
            }
        }
        return s
    }

    /// Plain words for a wake reason from the log. Matches whole tokens (split on anything that isn't a
    /// letter or digit) and the first token that means something wins.
    nonisolated static func plainReason(_ reason: String) -> String {
        let words: [String: String] = [
            "wifibt": "Wi-Fi or Bluetooth", "arpt": "Wi-Fi", "wifi": "Wi-Fi",
            "bluetooth": "Bluetooth", "bt": "Bluetooth",
            "pwrbtn": "the power button", "lid": "the lid", "usb": "a USB device",
            "rtc": "scheduled maintenance", "maintenance": "scheduled maintenance",
            "useractivity": "you",
        ]
        let tokens = reason.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        for t in tokens {
            // "LID0" counts as "lid": ignore trailing digits.
            if let w = words[String(t)] ?? words[String(t.reversed().drop(while: \.isNumber).reversed())] { return w }
        }
        return "other"
    }

    /// Counts "Wake" and "DarkWake" entries between `from` and `to` and tallies their reasons.
    /// Log lines look like `2026-11-20 14:34:05 +0545 Wake <tab>Wake from Deep Idle [CDNVA] : due to <reason> Using BATT (Charge:73%)`.
    nonisolated static func parse(log: String, from: Date, to: Date) -> WakeSummary {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        var summary = WakeSummary()
        for line in log.split(whereSeparator: \.isNewline) {
            guard line.count > 26, line.first?.isNumber == true else { continue }
            let stamp = String(line.prefix(25))
            guard let date = fmt.date(from: stamp), date >= from, date < to else { continue }
            let rest = line.dropFirst(25).drop(while: { $0 == " " })
            let kind = rest.prefix(while: { !$0.isWhitespace })
            guard kind == "Wake" || kind == "DarkWake" else { continue }
            let body = rest.dropFirst(kind.count).drop(while: { $0.isWhitespace })
            guard body.hasPrefix("Wake from") || body.hasPrefix("DarkWake from") else { continue }
            summary.wakes += 1
            var reason = ""
            if let range = body.range(of: "due to ") {
                reason = String(body[range.upperBound...])
                if let end = reason.range(of: " Using ") { reason = String(reason[..<end.lowerBound]) }
            }
            summary.causes[plainReason(reason), default: 0] += 1
        }
        return summary
    }

    private final class Stop: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false
        var value: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
        func set() { lock.lock(); stopped = true; lock.unlock() }
    }

    /// Runs `pmset -g log` with a 20 s deadline and a 32 MB cap. Returns nil when it had to be stopped
    /// or couldn't run. Keeps reading while it waits so the pipe never fills.
    private nonisolated static func runPmset() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "log"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let timedOut = Stop()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20) {
            if p.isRunning { timedOut.set(); p.terminate() }
        }
        let cap = 32 * 1024 * 1024
        var data = Data()
        let handle = pipe.fileHandleForReading
        while !timedOut.value {
            guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
            data.append(chunk)
            if data.count > cap { timedOut.set(); p.terminate(); break }
        }
        if timedOut.value { p.waitUntilExit(); return nil }
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// One dismissible overnight line on the deck home.
struct SleepDrainLineView: View {
    let report: SleepDrain.Report

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "battery.50percent").font(.system(size: 11)).foregroundStyle(.secondary)
            Text(SleepDrain.text(for: report))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button { withAnimation(Deck.animation) { SleepDrain.shared.dismiss() } } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss")
            .accessibilityLabel("Dismiss overnight battery note")
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
        .onAppear { SleepDrain.shared.refresh() }
    }
}
