import Foundation
import Testing
@testable import VibeCheck

struct ClipboardTests {
    @Test func skipsPrivateSecureIgnoredAndEmpty() {
        let ignored: Set<String> = ["com.1password.1password"]
        let text: Set<String> = ["public.utf8-plain-text"]
        #expect(!ClipboardHistory.shouldSkip(types: text, bundleID: "com.apple.Safari", ignored: ignored, secureInput: false))
        #expect(ClipboardHistory.shouldSkip(types: text, bundleID: "com.apple.Safari", ignored: ignored, secureInput: true))
        #expect(ClipboardHistory.shouldSkip(types: text, bundleID: "com.1password.1password", ignored: ignored, secureInput: false))
        #expect(ClipboardHistory.shouldSkip(types: text.union(["org.nspasteboard.ConcealedType"]), bundleID: nil, ignored: ignored, secureInput: false))
        #expect(ClipboardHistory.shouldSkip(types: text.union(["org.nspasteboard.TransientType"]), bundleID: nil, ignored: ignored, secureInput: false))
        #expect(ClipboardHistory.shouldSkip(types: [], bundleID: nil, ignored: ignored, secureInput: false))
    }

    @Test func insertDedupesAndTrims() {
        let a = ClipItem(content: .text("a")), b = ClipItem(content: .text("b"))
        var list = ClipboardHistory.inserted(a, into: [], limit: 2)
        list = ClipboardHistory.inserted(b, into: list, limit: 2)
        list = ClipboardHistory.inserted(ClipItem(content: .text("a")), into: list, limit: 2)
        #expect(list.map(\.content) == [.text("a"), .text("b")])
        list = ClipboardHistory.inserted(ClipItem(content: .text("c")), into: list, limit: 2)
        #expect(list.map(\.content) == [.text("c"), .text("a")])
    }

    @Test func previewIsFirstNonEmptyLineCut() {
        #expect(ClipItem.preview("\n  hello world  \nsecond") == "hello world")
        #expect(ClipItem.preview(String(repeating: "x", count: 100)).count == 80)
        #expect(ClipItem(content: .files([URL(fileURLWithPath: "/tmp/a.pdf")])).title == "a.pdf")
    }

    @MainActor @Test func clipQueryShowsOnlyClipboardRows() {
        let rows = [DeckCommand(id: "module.cpu", title: "Open CPU", symbol: "cpu") {},
                    DeckCommand(id: "clip.1", title: "hello there", symbol: "doc") {},
                    DeckCommand(id: "clip.2", title: "git push", symbol: "doc") {}]
        #expect(DeckCommands.filter(rows, query: "clip", recent: []).map(\.id) == ["clip.1", "clip.2"])
        #expect(DeckCommands.filter(rows, query: "clip git", recent: []).map(\.id) == ["clip.2"])
        #expect(DeckCommands.filter(rows, query: "open", recent: []).map(\.id) == ["module.cpu"])
    }

    @MainActor @Test func keepsTextAcrossRestartsOnlyWhenAsked() throws {
        let suite = "clip-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        defaults.set(true, forKey: "clipboardHistory")
        defaults.set(true, forKey: "clipboardKeepAcrossRestarts")

        let first = ClipboardHistory(defaults: defaults, fileURL: file)
        first.record(ClipItem(content: .text("kept")))
        first.record(ClipItem(content: .image(Data([1, 2, 3]))))
        let perms = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        #expect(ClipboardHistory(defaults: defaults, fileURL: file).items.map(\.content) == [.text("kept")])

        first.keepAcrossRestarts = false
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @MainActor @Test func defaultsAreOffWithPasswordManagersIgnored() throws {
        let suite = "clip-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clip = ClipboardHistory(defaults: defaults, fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json"))
        #expect(!clip.isEnabled && !clip.keepAcrossRestarts && clip.limit == 50)
        #expect(clip.ignoredApps.contains("com.1password.1password"))
        #expect(!SettingsBackup.keys.contains("clipboardHistory"))
        #expect(SettingsBackup.keys.contains("clipboardSnippets"))
    }
}
