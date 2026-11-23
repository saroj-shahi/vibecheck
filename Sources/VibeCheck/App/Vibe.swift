import Foundation
import SwiftUI

/// The Mac's overall state, in one word.
enum Vibe: Int, Comparable, Sendable {
    case vibing, mid, cooked

    static func < (lhs: Vibe, rhs: Vibe) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .vibing: String(localized: "Vibing", comment: "Brand term for the Mac's state; keep it casual")
        case .mid: String(localized: "Mid", comment: "Brand term for the Mac's state; keep it casual")
        case .cooked: String(localized: "Cooked", comment: "Brand term for the Mac's state; keep it casual")
        }
    }

    /// How much of the ring is filled: full when healthy, emptier as things get worse.
    var ringFill: Double {
        switch self {
        case .vibing: 1
        case .mid: 0.66
        case .cooked: 0.33
        }
    }

    var color: Color {
        switch self {
        case .vibing: .mint
        case .mid: .yellow
        case .cooked: .red
        }
    }
}

/// Everything the score looks at, as plain values (easy to test).
struct VibeInput: Sendable {
    var cpuRecent: Double = 0              // average CPU over the last ~30 s, 0...1
    var memoryPressure: MemoryPressure = .normal
    var hottest: Double? = nil             // °C
    var startupDiskFree: Double? = nil     // fraction free, 0...1
    var batteryOnBattery: Double? = nil    // charge 0...1, only when running on battery
    var thermalState: ProcessInfo.ThermalState = .nominal
    /// Bytes of swap added over the last ~60 s (0 when shrinking or unknown).
    var swapGrowth: Double = 0
    /// macOS's estimate of minutes to empty, only when running on battery.
    var batteryMinutesLeft: Int? = nil
    /// The level each module had on the previous sample. A level is kept until the value falls below a
    /// lower "exit" threshold, so a value hovering at a threshold can't flip the verdict back and forth.
    var held: [Module: Vibe] = [:]
}

/// Enter and exit thresholds for one numeric signal (higher is worse).
struct VibeThresholds: Sendable {
    var midEnter: Double, midExit: Double, cookedEnter: Double, cookedExit: Double

    func level(_ value: Double, held: Vibe?) -> Vibe? {
        let held = held ?? .vibing
        if value >= cookedEnter || (held == .cooked && value >= cookedExit) { return .cooked }
        if value >= midEnter || (held >= .mid && value >= midExit) { return .mid }
        return nil
    }

    static let cpu = VibeThresholds(midEnter: 0.60, midExit: 0.50, cookedEnter: 0.85, cookedExit: 0.75)
    static let temperature = VibeThresholds(midEnter: 80, midExit: 76, cookedEnter: 90, cookedExit: 86)
    /// Swap growth that, with memory already tight, means the Mac is paging hard: 256 MB a minute.
    static let swapGrowthPerMinute: Double = 256 * 1_048_576
    /// On battery with charge to spare, fewer minutes left than this means something is draining it fast.
    static let fastDrainMinutes = 60
}

struct VibeReport: Equatable, Sendable {
    var vibe: Vibe
    var verdict: String
    /// The module behind the verdict (its tile gets outlined); nil while vibing.
    var culprit: Module? = nil
    /// A few words for beside the menu bar ring ("CPU 96%"); nil while vibing.
    var badge: String? = nil
}

enum VibeScore {
    /// Each problem found, with how bad it is, which module it belongs to and a short badge for the menu
    /// bar. Worst first.
    static func reasons(_ input: VibeInput) -> [(Vibe, String, Module, String)] {
        var found: [(Vibe, String, Module, String)] = []
        let cpu = Int((input.cpuRecent * 100).rounded())
        switch VibeThresholds.cpu.level(input.cpuRecent, held: input.held[.cpu]) {
        case .cooked: found.append((.cooked, String(localized: "CPU has been pinned at \(cpu)%", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .cpu, String(localized: "CPU \(cpu)%", comment: "Short menu bar badge")))
        case .mid: found.append((.mid, String(localized: "CPU has been busy at \(cpu)%", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .cpu, String(localized: "CPU \(cpu)%", comment: "Short menu bar badge")))
        default: break
        }

        switch input.memoryPressure {
        case .critical: found.append((.cooked, String(localized: "memory pressure is critical", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .memory, String(localized: "Memory", comment: "Short menu bar badge")))
        case .warning where input.swapGrowth >= VibeThresholds.swapGrowthPerMinute:
            found.append((.cooked, String(localized: "memory is tight and macOS is swapping to disk", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .memory, String(localized: "Swapping", comment: "Short menu bar badge")))
        case .warning: found.append((.mid, String(localized: "memory is getting tight", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .memory, String(localized: "Memory", comment: "Short menu bar badge")))
        case .normal: break
        }

        if let t = input.hottest {
            switch VibeThresholds.temperature.level(t, held: input.held[.sensors]) {
            case .cooked: found.append((.cooked, String(localized: "it's running hot at \(Int(t)) °C", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .sensors, String(localized: "\(Int(t)) °C", comment: "Short menu bar badge")))
            case .mid: found.append((.mid, String(localized: "it's warm at \(Int(t)) °C", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .sensors, String(localized: "\(Int(t)) °C", comment: "Short menu bar badge")))
            default: break
            }
        }

        if let free = input.startupDiskFree {
            let pct = Int((free * 100).rounded())
            if free < 0.05 { found.append((.cooked, String(localized: "only \(pct)% disk space left", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .disk, String(localized: "Disk \(pct)% free", comment: "Short menu bar badge"))) }
            else if free < 0.10 { found.append((.mid, String(localized: "disk is \(100 - pct)% full", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .disk, String(localized: "Disk \(pct)% free", comment: "Short menu bar badge"))) }
        }

        if let battery = input.batteryOnBattery {
            let pct = Int((battery * 100).rounded())
            if battery < 0.10 { found.append((.cooked, String(localized: "battery is at \(pct)%", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .battery, String(localized: "Battery \(pct)%", comment: "Short menu bar badge"))) }
            else if battery < 0.20 { found.append((.mid, String(localized: "battery is at \(pct)%", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .battery, String(localized: "Battery \(pct)%", comment: "Short menu bar badge"))) }
            else if let minutes = input.batteryMinutesLeft, minutes > 0, minutes < VibeThresholds.fastDrainMinutes {
                found.append((.mid, String(localized: "battery is draining fast, about \(minutes) min left", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .battery, String(localized: "~\(minutes) min left", comment: "Short menu bar badge")))
            }
        }

        switch input.thermalState {
        case .critical: found.append((.cooked, String(localized: "macOS is throttling to cool down", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .sensors, String(localized: "Throttling", comment: "Short menu bar badge")))
        case .serious: found.append((.mid, String(localized: "macOS is starting to throttle", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .sensors, String(localized: "Throttling", comment: "Short menu bar badge")))
        default: break
        }
        return found.sorted { $0.0 > $1.0 }
    }

    static func evaluate(_ input: VibeInput) -> Vibe {
        reasons(input).map(\.0).max() ?? .vibing
    }

    /// Each module's worst level in this sample: feed it back as `VibeInput.held` next time.
    static func held(_ input: VibeInput) -> [Module: Vibe] {
        reasons(input).reduce(into: [:]) { result, reason in result[reason.2] = max(result[reason.2] ?? .vibing, reason.0) }
    }

    /// The module whose problem sets the verdict at this level; nil while vibing or settling down.
    static func culprit(for vibe: Vibe, input: VibeInput) -> Module? {
        guard vibe != .vibing else { return nil }
        return reasons(input).first { $0.0 >= vibe }?.2
    }

    /// The short badge for the same problem as `culprit`; nil while vibing or settling down.
    static func badge(for vibe: Vibe, input: VibeInput) -> String? {
        guard vibe != .vibing else { return nil }
        return reasons(input).first { $0.0 >= vibe }?.3
    }

    /// The memory culprit by app: growth over the last hour when it's big, else who uses the most.
    nonisolated static func memoryLine(_ app: (name: String, footprint: Double, processCount: Int, growth: Double?, minutes: Int?)) -> String {
        if let growth = app.growth, growth >= 500_000_000, let minutes = app.minutes {
            let span = minutes >= 55 ? String(localized: "hour") : String(localized: "\(minutes) min")
            let label = app.processCount > 1 ? String(localized: "\(app.name) (\(app.processCount) processes)") : app.name
            return String(localized: "\(label) grew \(Fmt.bytes(growth)) in the last \(span).")
        }
        return String(localized: "\(app.name) is using the most memory, \(Fmt.bytes(app.footprint)).")
    }

    /// One friendly sentence for the deck header.
    static func verdict(for vibe: Vibe, input: VibeInput, topApp: (name: String, cpu: Double)?,
                        memoryApp: (name: String, footprint: Double, processCount: Int, growth: Double?, minutes: Int?)? = nil) -> String {
        var loudest = topApp.flatMap { app in
            app.cpu >= 5 ? String(localized: "\(app.name) is the loudest at \(Int(app.cpu.rounded()))% CPU.") : nil
        }
        if vibe != .vibing, culprit(for: vibe, input: input) == .memory, let mem = memoryApp {
            loudest = memoryLine(mem)
        }
        guard vibe != .vibing else {
            return String(localized: "Your Mac is vibing.") + " " + (loudest ?? String(localized: "Nothing's working hard."))
        }
        let reason = reasons(input).first { $0.0 >= vibe }?.1 ?? String(localized: "things are settling down")
        let opener = vibe == .cooked ? String(localized: "Your Mac is cooked") : String(localized: "Kinda mid")
        return String(localized: "\(opener): \(reason).") + (loudest.map { " " + $0 } ?? "")
    }
}

/// Only lets the vibe change after the new level has been seen on consecutive samples,
/// so the menu bar never flickers between states.
struct VibeTracker {
    private(set) var current: Vibe = .vibing
    private var pending: Vibe?
    private var pendingCount = 0
    private var primed = false
    let required: Int

    init(required: Int = 2) { self.required = max(1, required) }

    @discardableResult
    mutating func update(_ observed: Vibe) -> Vibe {
        guard primed else {
            primed = true
            current = observed
            return current
        }
        if observed == current {
            pending = nil
            pendingCount = 0
        } else if observed == pending {
            pendingCount += 1
        } else {
            pending = observed
            pendingCount = 1
        }
        if let pending, pendingCount >= required {
            current = pending
            self.pending = nil
            pendingCount = 0
        }
        return current
    }
}
