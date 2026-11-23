import Foundation
import Testing
@testable import VibeCheck

@Suite struct UpdateCheckerTests {
    static let json = """
    {"tag_name":"v1.6.0","html_url":"https://github.com/o/r/releases/tag/v1.6.0","body":"Notes","draft":false,"prerelease":false,
     "assets":[{"name":"notes.txt","browser_download_url":"https://github.com/o/r/releases/download/v1.6.0/notes.txt"},{"name":"VibeCheck-1.6.0.dmg","browser_download_url":"https://github.com/o/r/releases/download/v1.6.0/VibeCheck.dmg"}]}
    """

    @Test func versionCompare() {
        #expect(UpdateChecker.compare("1.5", "1.5.0") == .orderedSame)
        #expect(UpdateChecker.compare("1.5", "1.10") == .orderedAscending)
        #expect(UpdateChecker.compare("2.0", "1.99.9") == .orderedDescending)
        #expect(UpdateChecker.compare("v1.5", "1.5") == .orderedSame)
        #expect(UpdateChecker.compare("1.6-beta.1", "1.6") == .orderedSame)
        #expect(UpdateChecker.isNewer("1.5.1", than: "1.5"))
        #expect(!UpdateChecker.isNewer("1.5", than: "1.5.0"))
    }

    @Test func parsesWithDMG() throws {
        let release = try #require(UpdateChecker.parse(Data(Self.json.utf8)))
        #expect(release.version == "1.6.0")
        #expect(release.assetURL?.absoluteString == "https://github.com/o/r/releases/download/v1.6.0/VibeCheck.dmg")
        #expect(release.notes == "Notes")
    }

    @Test func parsesWithZip() throws {
        let text = """
        {"tag_name":"v1.7.0","html_url":"https://github.com/o/r/releases/tag/v1.7.0","assets":[
         {"name":"VibeCheck.zip.sha256","browser_download_url":"https://github.com/o/r/releases/download/v1.7.0/VibeCheck.zip.sha256"},
         {"name":"VibeCheck.zip","browser_download_url":"https://github.com/o/r/releases/download/v1.7.0/VibeCheck.zip"}]}
        """
        let release = try #require(UpdateChecker.parse(Data(text.utf8)))
        #expect(release.version == "1.7.0")
        #expect(release.assetURL?.absoluteString == "https://github.com/o/r/releases/download/v1.7.0/VibeCheck.zip")
        #expect(release.pageURL.absoluteString == "https://github.com/o/r/releases/tag/v1.7.0")
    }

    @Test func prefersZipOverDMG() throws {
        let text = """
        {"tag_name":"v1.7.0","html_url":"https://github.com/o/r/releases/tag/v1.7.0","assets":[
         {"name":"VibeCheck.dmg","browser_download_url":"https://github.com/o/r/releases/download/v1.7.0/VibeCheck.dmg"},
         {"name":"VibeCheck.zip","browser_download_url":"https://github.com/o/r/releases/download/v1.7.0/VibeCheck.zip"}]}
        """
        let release = try #require(UpdateChecker.parse(Data(text.utf8)))
        #expect(release.assetURL?.lastPathComponent == "VibeCheck.zip")
        // An untrusted zip is dropped, and the trusted DMG is used instead.
        let badZip = text.replacingOccurrences(of: "https://github.com/o/r/releases/download/v1.7.0/VibeCheck.zip",
                                               with: "https://evil.example/VibeCheck.zip")
        #expect(UpdateChecker.parse(Data(badZip.utf8))?.assetURL?.lastPathComponent == "VibeCheck.dmg")
    }

    @Test func updateCommandsAreTerminalOnly() {
        let commands = UpdateChecker.updateCommands.map(\.command)
        #expect(commands == ["brew upgrade --cask saroj-shahi/tap/vibecheck",
                             "curl -fsSL https://raw.githubusercontent.com/saroj-shahi/vibecheck/main/scripts/install.sh | bash"])
    }

    @Test func parsesWithoutAsset() throws {
        let text = #"{"tag_name":"1.7","html_url":"https://github.com/o/r/releases/tag/1.7","assets":[]}"#
        let release = try #require(UpdateChecker.parse(Data(text.utf8)))
        #expect(release.version == "1.7")
        #expect(release.assetURL == nil)
        #expect(release.notes == nil)
    }

    @Test func rejectsPrereleaseAndGarbage() {
        let pre = #"{"tag_name":"v2","html_url":"https://x","prerelease":true}"#
        #expect(UpdateChecker.parse(Data(pre.utf8)) == nil)
        #expect(UpdateChecker.parse(Data("nope".utf8)) == nil)
    }

    @Test func interpretStates() throws {
        #expect(try UpdateChecker.interpret(data: Data(), status: 404, current: "1.5") == .noInfo)
        #expect(throws: UpdateCheckError.badResponse(500)) { try UpdateChecker.interpret(data: Data(), status: 500, current: "1.5") }
        #expect(try UpdateChecker.interpret(data: Data(Self.json.utf8), status: 200, current: "1.6") == .upToDate)
        guard case .available(let r) = try UpdateChecker.interpret(data: Data(Self.json.utf8), status: 200, current: "1.5") else {
            Issue.record("expected available"); return
        }
        #expect(r.version == "1.6.0")
    }

    @Test func throttle() {
        let now = Date()
        #expect(UpdateChecker.shouldAutoCheck(enabled: true, last: nil, now: now))
        #expect(!UpdateChecker.shouldAutoCheck(enabled: false, last: nil, now: now))
        #expect(!UpdateChecker.shouldAutoCheck(enabled: true, last: now.addingTimeInterval(-3600), now: now))
        #expect(UpdateChecker.shouldAutoCheck(enabled: true, last: now.addingTimeInterval(-25 * 3600), now: now))
    }

    @Test func notifyOncePerVersion() {
        #expect(UpdateChecker.shouldNotify(version: "1.6", lastNotified: nil))
        #expect(!UpdateChecker.shouldNotify(version: "1.6.0", lastNotified: "1.6"))
        #expect(UpdateChecker.shouldNotify(version: "1.7", lastNotified: "1.6"))
        #expect(!UpdateChecker.shouldNotify(version: "1.5", lastNotified: "1.6"))  // rolled-back release
    }

    @Test func onlyGitHubHTTPSLinksAreKept() {
        #expect(UpdateChecker.trustedURL("https://github.com/o/r/releases/tag/v1") != nil)
        #expect(UpdateChecker.trustedURL("https://objects.githubusercontent.com/x.dmg") != nil)
        #expect(UpdateChecker.trustedURL("http://github.com/o/r") == nil)
        #expect(UpdateChecker.trustedURL("file:///Applications/Calculator.app") == nil)
        #expect(UpdateChecker.trustedURL("https://github.com.evil.example/x.dmg") == nil)
        #expect(UpdateChecker.trustedURL("x-apple.systempreferences:com.apple") == nil)
        let bad = """
        {"tag_name":"v2","html_url":"https://evil.example/r","assets":[]}
        """
        #expect(UpdateChecker.parse(Data(bad.utf8)) == nil)
        let badAsset = """
        {"tag_name":"v2","html_url":"https://github.com/o/r","assets":[{"name":"a.dmg","browser_download_url":"https://evil.example/a.dmg"}]}
        """
        #expect(UpdateChecker.parse(Data(badAsset.utf8))?.assetURL == nil)
    }

    @MainActor @Test func failedCheckDoesNotStartTheWait() async throws {
        let suite = "UpdateCheckerTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let checker = UpdateChecker()
        checker.defaults = defaults
        checker.repository = "o/r"
        checker.fetch = { _ in throw URLError(.notConnectedToInternet) }
        await checker.check()
        #expect(defaults.object(forKey: UpdateChecker.lastCheckKey) == nil)
    }

    @MainActor @Test func checkerUsesInjectedFetch() async throws {
        let suite = "UpdateCheckerTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let checker = UpdateChecker()
        checker.defaults = defaults
        checker.repository = "o/r"
        checker.currentVersion = "1.5"
        var found: [String] = []
        checker.onNewVersion = { found.append($0.version) }

        checker.fetch = { _ in (Data(), 404) }
        await checker.check()
        #expect(checker.state == .noInfo)

        checker.fetch = { _ in (Data(Self.json.utf8), 200) }
        await checker.check(automatic: true)
        await checker.check(automatic: true)
        #expect(found == ["1.6.0"])
        #expect(defaults.object(forKey: UpdateChecker.lastCheckKey) is Date)

        checker.fetch = { _ in throw URLError(.notConnectedToInternet) }
        await checker.check()
        if case .failed = checker.state {} else { Issue.record("expected failed") }
    }
}
