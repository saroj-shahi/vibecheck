import Foundation
import Observation

/// What the latest GitHub release says.
struct ReleaseInfo: Equatable, Sendable {
    var version: String
    /// The release notes page; the only link the app opens.
    var pageURL: URL
    /// The app archive the release ships (`VibeCheck.zip`, or a `.dmg` on older releases). The app never
    /// downloads it: updates go through Terminal (see `UpdateChecker.updateCommands`).
    var assetURL: URL?
    var notes: String?
}

/// One way to update from Terminal, shown with a Copy button.
struct UpdateCommand: Identifiable, Equatable, Sendable {
    var id: String { command }
    var label: String
    var command: String
}

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(ReleaseInfo)
    /// No releases yet, or the repository is private: nothing to say, and not an error.
    case noInfo
    case failed(String)
}

enum UpdateCheckError: Error, Equatable {
    case badResponse(Int)
    case unreadable
    case offline
}

/// Looks for a newer VibeCheck on GitHub Releases. Plain URLSession, no account, no extra dependencies.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    private(set) var state: UpdateState = .idle

    /// The network call; replaceable so tests never touch the network.
    @ObservationIgnored var fetch: @Sendable (URLRequest) async throws -> (Data, Int) = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
    @ObservationIgnored var defaults: UserDefaults = .standard
    @ObservationIgnored var currentVersion: String = UpdateChecker.bundleVersion
    @ObservationIgnored var repository: String? = UpdateChecker.bundleRepository
    @ObservationIgnored var now: () -> Date = { Date() }
    /// Called when an automatic check finds a version the owner hasn't been told about.
    @ObservationIgnored var onNewVersion: ((ReleaseInfo) -> Void)?
    @ObservationIgnored private var loop: Task<Void, Never>?

    static let lastCheckKey = "updateLastCheck", lastNotifiedKey = "updateLastNotified"
    nonisolated static let interval: TimeInterval = 24 * 3600
    nonisolated static let firstCheckDelay: Duration = .seconds(60)

    nonisolated static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    nonisolated static var bundleRepository: String? {
        (Bundle.main.object(forInfoDictionaryKey: "VCUpdateRepository") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: Automatic checks

    /// First check about a minute after launch, then whenever 24 h have passed (looked at hourly).
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            try? await Task.sleep(for: Self.firstCheckDelay)
            while !Task.isCancelled {
                await self?.automaticCheckIfDue()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func automaticCheckIfDue() async {
        let last = defaults.object(forKey: Self.lastCheckKey) as? Date
        guard Self.shouldAutoCheck(enabled: AppSettings.shared.checkForUpdates, last: last, now: now()) else { return }
        await check(automatic: true)
    }

    // MARK: Checking

    /// Manual checks always run; automatic ones also notify once per version.
    func check(automatic: Bool = false) async {
        guard state != .checking else { return }
        guard let repository, let request = Self.request(repository: repository, version: currentVersion) else {
            state = .noInfo
            return
        }
        state = .checking
        do {
            let (data, status) = try await fetch(request)
            let result = try Self.interpret(data: data, status: status, current: currentVersion)
            state = result
            // Only a real answer starts the 24 h wait; after a failure the hourly tick tries again.
            defaults.set(now(), forKey: Self.lastCheckKey)
            if automatic, case .available(let release) = result {
                let last = defaults.string(forKey: Self.lastNotifiedKey)
                if Self.shouldNotify(version: release.version, lastNotified: last) {
                    defaults.set(release.version, forKey: Self.lastNotifiedKey)
                    onNewVersion?(release)
                }
            }
        } catch let error as UpdateCheckError {
            state = .failed(Self.reason(error))
        } catch {
            state = .failed(Self.reason(.offline))
        }
    }

    // MARK: Updating

    /// VibeCheck isn't notarized, so it updates the way it was installed: from Terminal.
    nonisolated static let brewCommand = "brew upgrade --cask saroj-shahi/tap/vibecheck"
    nonisolated static let curlCommand =
        "curl -fsSL https://raw.githubusercontent.com/saroj-shahi/vibecheck/main/scripts/install.sh | bash"

    nonisolated static var updateCommands: [UpdateCommand] {
        [UpdateCommand(label: String(localized: "Installed with Homebrew"), command: brewCommand),
         UpdateCommand(label: String(localized: "Installed with the install script"), command: curlCommand)]
    }

    // MARK: Pure helpers

    nonisolated static func request(repository: String, version: String) -> URLRequest? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("VibeCheck/\(version)", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Turns a response into a state. A 404 means no release info, quietly.
    nonisolated static func interpret(data: Data, status: Int, current: String) throws -> UpdateState {
        if status == 404 { return .noInfo }
        guard (200..<300).contains(status) else { throw UpdateCheckError.badResponse(status) }
        guard let release = parse(data) else { throw UpdateCheckError.unreadable }
        return isNewer(release.version, than: current) ? .available(release) : .upToDate
    }

    nonisolated static func parse(_ data: Data) -> ReleaseInfo? {
        struct Asset: Decodable { var name: String; var browser_download_url: String }
        struct Release: Decodable {
            var tag_name: String; var html_url: String; var body: String?
            var draft: Bool?; var prerelease: Bool?; var assets: [Asset]?
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              release.draft != true, release.prerelease != true,
              let page = trustedURL(release.html_url) else { return nil }
        var tag = release.tag_name.trimmingCharacters(in: .whitespaces)
        if tag.hasPrefix("v") || tag.hasPrefix("V") { tag.removeFirst() }
        guard !tag.isEmpty else { return nil }
        // Prefer the zip (current releases); fall back to a DMG so older releases still read.
        func asset(_ suffix: String) -> URL? {
            release.assets?.first { $0.name.lowercased().hasSuffix(suffix) }.flatMap { trustedURL($0.browser_download_url) }
        }
        let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReleaseInfo(version: tag, pageURL: page, assetURL: asset(".zip") ?? asset(".dmg"),
                           notes: (notes?.isEmpty ?? true) ? nil : notes)
    }

    /// Links from the response are opened by the app, so only https on GitHub's own hosts are kept.
    nonisolated static func trustedURL(_ string: String) -> URL? {
        guard let url = URL(string: string), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return nil }
        let trusted = host == "github.com" || host.hasSuffix(".github.com")
            || host == "githubusercontent.com" || host.hasSuffix(".githubusercontent.com")
        return trusted ? url : nil
    }

    /// Numeric, dot-separated components; missing ones are 0. Anything after the first non-digit in a
    /// component is ignored ("2-beta" reads as 2), and a component with no leading digits counts as 0.
    nonisolated static func components(_ version: String) -> [Int] {
        var text = version.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        // Drop build metadata and pre-release suffixes ("1.5.0-beta.1", "1.5+7").
        if let cut = text.firstIndex(where: { $0 == "-" || $0 == "+" || $0 == " " }) { text = String(text[..<cut]) }
        return text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    nonisolated static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = components(a), y = components(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    nonisolated static func shouldAutoCheck(enabled: Bool, last: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval || last > now
    }

    nonisolated static func shouldNotify(version: String, lastNotified: String?) -> Bool {
        guard let lastNotified else { return true }
        return isNewer(version, than: lastNotified)
    }

    nonisolated static func reason(_ error: UpdateCheckError) -> String {
        switch error {
        case .offline: String(localized: "Couldn't reach GitHub.")
        case .badResponse(403), .badResponse(429): String(localized: "GitHub asked us to wait. Try again later.")
        case .badResponse(let code): String(localized: "GitHub answered \(code).")
        case .unreadable: String(localized: "GitHub's answer didn't make sense.")
        }
    }
}
