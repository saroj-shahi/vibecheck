import AppKit
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Optional, on demand "Explain my Mac": Apple's on-device model turns a short facts string into three
/// short phrases. Off by default; nothing is sent anywhere. The pure parts (facts, post-check, UI state)
/// compile everywhere and are tested; only `generate` touches the model.
enum ExplainAvailability: Equatable, Sendable {
    case unavailable                 // no model, old macOS, or a Mac that can't run it: the feature doesn't exist
    case needsSetup(String)          // fixable: shown as a disabled toggle with this one-line reason
    case available
}

enum ExplainToggleState: Equatable, Sendable {
    case hidden
    case enabled
    case disabled(reason: String)
}

/// Why the system model can't be used, mirrored so the mapping is testable without FoundationModels.
enum ExplainUnavailableReason: Sendable {
    case deviceNotEligible, appleIntelligenceOff, modelNotReady, other
}

/// What the card shows.
enum ExplainCardState: Equatable, Sendable {
    case idle
    case thinking
    case result(headline: String, detail: String)
    /// The rule verdict sentence plus "Couldn't explain this time."
    case fallback(verdict: String)
}

struct ExplainFacts: Sendable {
    var vibe: String
    var verdict: String
    var cpuAverage: Double               // 0...1, last ~30 s
    var memoryPressure: String
    var swapGrowing: Bool
    var thermal: String
    var onBattery: Bool
    var batteryMinutes: Int?
    var topCPU: [(name: String, cpu: Double)] = []
    var memoryApp: (name: String, footprint: Double, processCount: Int, growth: Double?, minutes: Int?)?
}

enum OnDeviceExplainer {
    nonisolated static let timeout: Duration = .seconds(10)

    // MARK: Pure

    nonisolated static func mapAvailability(available: Bool, reason: ExplainUnavailableReason?) -> ExplainAvailability {
        if available { return .available }
        switch reason {
        case .appleIntelligenceOff: return .needsSetup(String(localized: "Turn on Apple Intelligence in System Settings first."))
        case .modelNotReady: return .needsSetup(String(localized: "Apple's on-device model is still downloading."))
        case .deviceNotEligible, .other, nil: return .unavailable
        }
    }

    nonisolated static func toggleState(for availability: ExplainAvailability) -> ExplainToggleState {
        switch availability {
        case .available: .enabled
        case .needsSetup(let reason): .disabled(reason: reason)
        case .unavailable: .hidden
        }
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

    /// The compact facts the model sees: numbers already formatted, nothing raw.
    nonisolated static func factsString(_ f: ExplainFacts) -> String {
        var lines = ["Vibe: \(f.vibe). \(f.verdict)"]
        lines.append("CPU 30 s average: \(Int((f.cpuAverage * 100).rounded()))%.")
        lines.append("Memory pressure: \(f.memoryPressure.lowercased()). Swap is \(f.swapGrowing ? "growing" : "not growing"). Thermal state: \(f.thermal).")
        if f.onBattery {
            lines.append(f.batteryMinutes.map { "On battery, \($0) minutes left." } ?? "On battery.")
        } else {
            lines.append("Plugged in or no battery.")
        }
        if !f.topCPU.isEmpty {
            lines.append("Top apps by CPU: " + f.topCPU.prefix(3).map { "\($0.name) \(Int($0.cpu.rounded()))%" }.joined(separator: ", ") + ".")
        }
        if let app = f.memoryApp {
            var line = "Top memory app: \(app.name), \(Fmt.bytes(app.footprint)), \(app.processCount) process\(app.processCount == 1 ? "" : "es")"
            if let growth = app.growth, growth >= 512 * 1_048_576, let minutes = app.minutes {
                line += ", grew \(Fmt.bytes(growth)) in the last \(minutes) minutes"
            }
            lines.append(line + ".")
        }
        return lines.joined(separator: "\n")
    }

    /// Same pick as `AppMemoryHistory.top()`, from the tracks `SystemStats` exposes.
    nonisolated static func topMemory(tracks: [AppMemoryKey: AppMemoryTrack], now: Date = Date())
        -> (name: String, footprint: Double, processCount: Int, growth: Double?, minutes: Int?)? {
        let current = tracks.values.compactMap { track in track.samples.last.map { (track, $0) } }
            .filter { now.timeIntervalSince($0.1.date) <= AppMemoryHistory.interval * 3 }
            .max { $0.1.footprint < $1.1.footprint }
        guard let (track, last) = current else { return nil }
        let g = AppMemoryHistory.growth(track.samples, now: now)
        return (track.name, last.footprint, last.processCount, g?.bytes, g?.minutes)
    }

    /// Well-known apps the model might name from its own knowledge; mentioning one that isn't in the facts is rejected.
    nonisolated static let commonApps = ["Chrome", "Safari", "Firefox", "Slack", "Xcode", "Spotify", "Docker", "Zoom", "Teams",
                                         "Photoshop", "Figma", "Notion", "Discord", "Steam", "Final Cut"]

    /// A number with its unit, normalized: "%" , "min", or "MB" (GB converted).
    nonisolated static func quantities(in text: String) -> [(value: Double, unit: String, wasGB: Bool)] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\d.])(\d+(?:\.\d+)?)\s*(%|gb|mb|minutes?|mins?)(?![a-z])"#,
                                                   options: .caseInsensitive) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let value = Double(ns.substring(with: m.range(at: 1))) else { return nil }
            switch ns.substring(with: m.range(at: 2)).lowercased() {
            case "%": return (value, "%", false)
            case "gb": return (value * 1024, "MB", true)
            case "mb": return (value, "MB", false)
            default: return (value, "min", false)
            }
        }
    }

    /// Light post-check: false when the text names a well-known app that isn't in the facts, or a number with
    /// %, GB, MB or min that no fact matches (GB within 0.05, others within 1).
    nonisolated static func passesPostCheck(_ texts: [String], facts: String) -> Bool {
        let text = texts.joined(separator: " ")
        let known = quantities(in: facts)
        for q in quantities(in: text) {
            let ok = known.contains { k in
                k.unit == q.unit && abs(k.value - q.value) <= ((k.wasGB || q.wasGB) ? 0.05 * 1024 : 1)
            }
            if !ok { return false }
        }
        let haystack = facts.lowercased()
        let lowered = text.lowercased()
        for name in commonApps {
            let n = name.lowercased()
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: n) + "\\b"
            let inText = lowered.range(of: pattern, options: .regularExpression) != nil
            let inFacts = haystack.range(of: pattern, options: .regularExpression) != nil
            if inText, !inFacts { return false }
        }
        return true
    }

    nonisolated static let instructions = """
        You explain a Mac's current state to its owner in calm, plain words. Use only the facts you are given. \
        If one app is responsible for the problem (high CPU or memory, or it grew), name that exact app from the facts \
        in the headline or the cause, and make the action about that app, for example "Quit Google Chrome" or "Close tabs in Google Chrome". \
        Never give generic advice when an app is named in the facts. Never invent numbers, apps or causes. \
        Never suggest commands, downloads, sudo, settings changes or deleting files. \
        Safe actions only: quit an app, close tabs, plug in, wait. If nothing is wrong, say the Mac is fine and suggest waiting.
        """

    // MARK: Availability

    nonisolated static func availability() -> ExplainAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return systemAvailability() }
        #endif
        return .unavailable
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct MacExplanation {
    @Guide(description: "What is going on, at most 10 words")
    var headline: String
    @Guide(description: "The likely cause, naming the specific app from the facts when one is responsible, at most 16 words")
    var likelyCause: String
    @Guide(description: "One safe action, naming the app when one is responsible, at most 12 words")
    var suggestedAction: String
}

@available(macOS 26, *)
extension OnDeviceExplainer {
    nonisolated static func systemAvailability() -> ExplainAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: return mapAvailability(available: true, reason: nil)
        case .unavailable(let reason):
            let mapped: ExplainUnavailableReason = switch reason {
            case .deviceNotEligible: .deviceNotEligible
            case .appleIntelligenceNotEnabled: .appleIntelligenceOff
            case .modelNotReady: .modelNotReady
            @unknown default: .other
            }
            return mapAvailability(available: false, reason: mapped)
        @unknown default: return .unavailable
        }
    }

    /// One fresh session per request; nil on any error, refusal or guardrail hit. The 10 s timeout lives in
    /// `ExplainCard`, so a model call that ignores cancellation can't keep the card on "Thinking…".
    nonisolated static func generate(facts: String) async -> (headline: String, detail: String)? {
        let session = LanguageModelSession(instructions: instructions)
        guard let result = try? await session.respond(to: "Facts about this Mac:\n\(facts)", generating: MacExplanation.self).content
        else { return nil }
        let headline = result.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let cause = result.likelyCause.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = result.suggestedAction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !headline.isEmpty, !cause.isEmpty, !action.isEmpty,
              passesPostCheck([headline, cause, action], facts: facts) else { return nil }
        return (headline, cause.hasSuffix(".") ? "\(cause) \(action)" : "\(cause). \(action)")
    }
}
#endif

/// The card's state on the deck home. Starts only from the ⌘K command.
@MainActor
@Observable
final class ExplainCard {
    static let shared = ExplainCard()
    private(set) var state: ExplainCardState = .idle
    @ObservationIgnored private var token = 0

    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var timer: Task<Void, Never>?

    func dismiss() {
        token += 1
        work?.cancel(); timer?.cancel()
        state = .idle
    }

    func start(stats: SystemStats?) {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *), let stats, OnDeviceExplainer.availability() == .available else { return }
        work?.cancel(); timer?.cancel()
        token += 1
        let mine = token
        state = .thinking
        let input = stats.vibeInput
        let verdict = stats.vibe.verdict
        let facts = OnDeviceExplainer.factsString(ExplainFacts(
            vibe: stats.vibe.vibe.title, verdict: verdict, cpuAverage: input.cpuRecent,
            memoryPressure: input.memoryPressure.label, swapGrowing: input.swapGrowth > 64 * 1_048_576,
            thermal: OnDeviceExplainer.thermalName(input.thermalState),
            onBattery: input.batteryOnBattery != nil, batteryMinutes: input.batteryMinutesLeft,
            topCPU: stats.processes.isEmpty ? [] : stats.topApps(by: \.cpu, limit: 3).map { ($0.name, $0.cpu) },
            memoryApp: OnDeviceExplainer.topMemory(tracks: stats.appMemoryTracks)))
        // The timer is independent of the model task: at 10 s the card falls back and a late result is dropped by the token.
        timer = Task { @MainActor in
            try? await Task.sleep(for: OnDeviceExplainer.timeout)
            guard !Task.isCancelled, mine == self.token, self.state == .thinking else { return }
            self.work?.cancel()
            self.state = .fallback(verdict: verdict)
        }
        work = Task { @MainActor in
            let out = await Task.detached { await OnDeviceExplainer.generate(facts: facts) }.value
            guard !Task.isCancelled, mine == self.token else { return }
            self.timer?.cancel()
            self.state = out.map { .result(headline: $0.headline, detail: $0.detail) } ?? .fallback(verdict: verdict)
        }
        #endif
    }
}

/// The "Explain my Mac" result on the deck home: headline, then cause and action, two lines at most.
struct ExplainCardView: View {
    private let card = ExplainCard.shared

    var body: some View {
        switch card.state {
        case .idle:
            EmptyView()
        case .thinking:
            row {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                Text("Thinking…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .result(let headline, let detail):
            row {
                Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(headline).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        case .fallback(let verdict):
            row {
                Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verdict).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text("Couldn't explain this time.").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            content()
            Spacer(minLength: 4)
            Button { card.dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss")
            .accessibilityLabel("Dismiss explanation")
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
    }
}
