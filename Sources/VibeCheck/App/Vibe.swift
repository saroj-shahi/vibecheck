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
        if input.cpuRecent >= 0.85 { found.append((.cooked, String(localized: "CPU has been pinned at \(cpu)%", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .cpu, String(localized: "CPU \(cpu)%", comment: "Short menu bar badge"))) }
        else if input.cpuRecent >= 0.6 { found.append((.mid, String(localized: "CPU has been busy at \(cpu)%", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .cpu, String(localized: "CPU \(cpu)%", comment: "Short menu bar badge"))) }

        switch input.memoryPressure {
        case .critical: found.append((.cooked, String(localized: "memory pressure is critical", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .memory, String(localized: "Memory", comment: "Short menu bar badge")))
        case .warning: found.append((.mid, String(localized: "memory is getting tight", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .memory, String(localized: "Memory", comment: "Short menu bar badge")))
        case .normal: break
        }

        if let t = input.hottest {
            if t >= 90 { found.append((.cooked, String(localized: "it's running hot at \(Int(t)) °C", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .sensors, String(localized: "\(Int(t)) °C", comment: "Short menu bar badge"))) }
            else if t >= 80 { found.append((.mid, String(localized: "it's warm at \(Int(t)) °C", comment: "Vibe reason, fits 'Your Mac is cooked: …'"), .sensors, String(localized: "\(Int(t)) °C", comment: "Short menu bar badge"))) }
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

    /// One friendly sentence for the deck header.
    static func verdict(for vibe: Vibe, input: VibeInput, topApp: (name: String, cpu: Double)?) -> String {
        let loudest = topApp.flatMap { app in
            app.cpu >= 5 ? String(localized: "\(app.name) is the loudest at \(Int(app.cpu.rounded()))% CPU.") : nil
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
