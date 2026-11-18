import Foundation
import Observation
import Security

/// Opt-in: asks Anthropic for Claude's real plan limits (5-hour and weekly) and hands them to the Agents module.
/// The only network host is api.anthropic.com; the Claude Code sign-in token is read from the Keychain for
/// each request and is never stored, logged or kept.
@Observable
@MainActor
final class ClaudeLiveLimits {
    static let shared = ClaudeLiveLimits()
    nonisolated static let defaultsKey = "claudeLiveLimits"
    /// Live limits older than this are ignored.
    nonisolated static let staleAfter: TimeInterval = 15 * 60
    nonisolated static let normalInterval: TimeInterval = 5 * 60
    nonisolated static let errorInterval: TimeInterval = 15 * 60

    enum Outcome: Equatable { case none, live, signInUnreadable, keychainDenied, noAnswer }

    var isOn: Bool = UserDefaults.standard.bool(forKey: ClaudeLiveLimits.defaultsKey) {
        didSet {
            guard oldValue != isOn else { return }
            UserDefaults.standard.set(isOn, forKey: Self.defaultsKey)
            if isOn { lastAttempt = .distantPast; outcome = .none; tick() } else { AgentUsageStore.shared.reapply() }
        }
    }

    private(set) var windows: [RateWindow] = []
    private(set) var fetchedAt: Date?
    private(set) var outcome: Outcome = .none
    @ObservationIgnored private var lastAttempt = Date.distantPast
    @ObservationIgnored private var fetching = false
    @ObservationIgnored private var timer: Timer?

    /// Live windows that may be shown right now (empty when off or stale).
    func currentWindows(now: Date = Date()) -> [RateWindow] { isOn ? windows : [] }

    func start() {
        guard timer == nil else { return }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { ClaudeLiveLimits.shared.tick() }
        }
    }

    /// Fetches when the setting and the Agents module are on and the next fetch is due.
    private func tick(now: Date = Date()) {
        // After a Keychain "Deny" don't ask again on a timer; switching the setting off and on retries.
        guard isOn, AppSettings.shared.isEnabled(.agents), !fetching, outcome != .keychainDenied else { return }
        let interval = (outcome == .signInUnreadable || outcome == .noAnswer) ? Self.errorInterval : Self.normalInterval
        guard now.timeIntervalSince(lastAttempt) >= interval else { return }
        fetching = true
        lastAttempt = now
        Task {
            let result = await Task.detached(priority: .utility) { await ClaudeLimitsClient.fetch() }.value
            ClaudeLiveLimits.shared.finish(result)
        }
    }

    private func finish(_ result: ClaudeLimitsClient.Result) {
        fetching = false
        guard isOn else { return }
        switch result {
        case .windows(let list):
            windows = list
            fetchedAt = Date()
            outcome = .live
        case .signInUnreadable: outcome = .signInUnreadable
        case .keychainDenied: outcome = .keychainDenied
        case .noAnswer: outcome = .noAnswer
        }
        AgentUsageStore.shared.reapply()
    }

    func statusText(now: Date = Date()) -> String {
        switch outcome {
        case .none: return "Waiting for the first update"
        case .signInUnreadable: return "Couldn't read the Claude Code sign-in"
        case .keychainDenied: return "Keychain access was denied. Switch this off and on to ask again."
        case .noAnswer: return "Anthropic didn't answer"
        case .live:
            guard let fetchedAt else { return "Waiting for the first update" }
            let minutes = max(0, Int(now.timeIntervalSince(fetchedAt) / 60))
            return "Live from Anthropic · updated " + (minutes == 0 ? "just now" : "\(minutes) min ago")
        }
    }

    /// Pure merge rule: fresh live limits replace Claude's limits; everything else is left as is.
    nonisolated static func merge(_ sample: AgentUsageSample, live: [RateWindow], fetchedAt: Date?, now: Date) -> AgentUsageSample {
        let live = live.filter { $0.resetsAt > now }   // a window that has reset since the fetch is wrong now
        guard !live.isEmpty, let fetchedAt, now.timeIntervalSince(fetchedAt) < staleAfter,
              let index = sample.agents.firstIndex(where: { $0.agent == .claude }) else { return sample }
        var merged = sample
        merged.agents[index].limits = live
        return merged
    }
}

/// Keychain and network access. Only called when the setting is on.
enum ClaudeLimitsClient {
    enum Result: Sendable {
        case windows([RateWindow])
        case signInUnreadable
        case keychainDenied
        case noAnswer
    }

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch(now: Date = Date()) async -> Result {
        let token: String
        switch readToken(now: now) {
        case .token(let value): token = value
        case .denied: return .keychainDenied
        case .unavailable: return .signInUnreadable
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return .noAnswer }
        let windows = parse(data)
        return windows.isEmpty ? .noAnswer : .windows(windows)
    }

    enum TokenRead { case token(String), denied, unavailable }

    /// The Claude Code OAuth access token. `denied` when the user turned down the Keychain prompt.
    static func readToken(now: Date) -> TokenRead {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecUserCanceled || status == errSecAuthFailed || status == errSecInteractionNotAllowed { return .denied }
        guard status == errSecSuccess, let data = item as? Data,
              let token = token(fromCredentials: data, now: now) else { return .unavailable }
        return .token(token)
    }

    static func token(fromCredentials data: Data, now: Date) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        if let expires = (oauth["expiresAt"] as? NSNumber)?.doubleValue,
           Date(timeIntervalSince1970: expires / 1000) <= now { return nil }
        return token
    }

    static func parse(_ data: Data) -> [RateWindow] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return [("five_hour", 300), ("seven_day", 10080)].compactMap { key, minutes -> RateWindow? in
            guard let window = object[key] as? [String: Any],
                  let used = (window["utilization"] as? NSNumber)?.doubleValue, used.isFinite else { return nil }
            guard let reset = date(window["resets_at"] as? String) else { return nil }   // no reset time: can't show it
            return RateWindow(usedPercent: min(max(used, 0), 100), windowMinutes: minutes, resetsAt: reset)
        }
    }

    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: string) { return d }
        // Fractional parts longer than milliseconds: drop them and retry.
        if let dot = string.firstIndex(of: "."),
           let end = string[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            return plain.date(from: String(string[..<dot]) + String(string[end...]))
        }
        return nil
    }
}
