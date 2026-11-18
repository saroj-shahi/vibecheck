import Foundation
import SwiftUI

/// The Mac's overall state, in one word.
enum Vibe: Int, Comparable, Sendable {
    case vibing, mid, cooked

    static func < (lhs: Vibe, rhs: Vibe) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .vibing: "Vibing"
        case .mid: "Mid"
        case .cooked: "Cooked"
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
}

struct VibeReport: Equatable, Sendable {
    var vibe: Vibe
    var verdict: String
    /// The module behind the verdict (its tile gets outlined); nil while vibing.
    var culprit: Module? = nil
}

enum VibeScore {
    /// Each problem found, with how bad it is and which module it belongs to. Worst first.
    static func reasons(_ input: VibeInput) -> [(Vibe, String, Module)] {
        var found: [(Vibe, String, Module)] = []
        let cpu = Int((input.cpuRecent * 100).rounded())
        if input.cpuRecent >= 0.85 { found.append((.cooked, "CPU has been pinned at \(cpu)%", .cpu)) }
        else if input.cpuRecent >= 0.6 { found.append((.mid, "CPU has been busy at \(cpu)%", .cpu)) }

        switch input.memoryPressure {
        case .critical: found.append((.cooked, "memory pressure is critical", .memory))
        case .warning: found.append((.mid, "memory is getting tight", .memory))
        case .normal: break
        }

        if let t = input.hottest {
            if t >= 90 { found.append((.cooked, "it's running hot at \(Int(t)) °C", .sensors)) }
            else if t >= 80 { found.append((.mid, "it's warm at \(Int(t)) °C", .sensors)) }
        }

        if let free = input.startupDiskFree {
            let pct = Int((free * 100).rounded())
            if free < 0.05 { found.append((.cooked, "only \(pct)% disk space left", .disk)) }
            else if free < 0.10 { found.append((.mid, "disk is \(100 - pct)% full", .disk)) }
        }

        if let battery = input.batteryOnBattery {
            let pct = Int((battery * 100).rounded())
            if battery < 0.10 { found.append((.cooked, "battery is at \(pct)%", .battery)) }
            else if battery < 0.20 { found.append((.mid, "battery is at \(pct)%", .battery)) }
        }

        switch input.thermalState {
        case .critical: found.append((.cooked, "macOS is throttling to cool down", .sensors))
        case .serious: found.append((.mid, "macOS is starting to throttle", .sensors))
        default: break
        }
        return found.sorted { $0.0 > $1.0 }
    }

    static func evaluate(_ input: VibeInput) -> Vibe {
        reasons(input).map(\.0).max() ?? .vibing
    }

    /// The module whose problem sets the verdict at this level; nil while vibing or settling down.
    static func culprit(for vibe: Vibe, input: VibeInput) -> Module? {
        guard vibe != .vibing else { return nil }
        return reasons(input).first { $0.0 >= vibe }?.2
    }

    /// One friendly sentence for the deck header.
    static func verdict(for vibe: Vibe, input: VibeInput, topApp: (name: String, cpu: Double)?) -> String {
        let loudest = topApp.flatMap { app in
            app.cpu >= 5 ? "\(app.name) is the loudest at \(Int(app.cpu.rounded()))% CPU." : nil
        }
        guard vibe != .vibing else {
            return "Your Mac is vibing. " + (loudest ?? "Nothing's working hard.")
        }
        let reason = reasons(input).first { $0.0 >= vibe }?.1 ?? "things are settling down"
        let opener = vibe == .cooked ? "Your Mac is cooked" : "Kinda mid"
        return "\(opener): \(reason)." + (loudest.map { " " + $0 } ?? "")
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
