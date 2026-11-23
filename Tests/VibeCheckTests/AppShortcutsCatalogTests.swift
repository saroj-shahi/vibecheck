import Foundation
import Testing

@Suite struct AppShortcutsCatalogTests {
    @Test func catalogHoldsEveryPhraseInCode() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/VibeCheck/App/Intents.swift"), encoding: .utf8)
        let catalogData = try Data(contentsOf: root.appendingPathComponent("Sources/VibeCheck/Resources/AppShortcuts.xcstrings"))
        let catalog = try #require(JSONSerialization.jsonObject(with: catalogData) as? [String: Any])
        let keys = Set((catalog["strings"] as? [String: Any] ?? [:]).keys)
        let provider = try #require(source.components(separatedBy: "struct VibeCheckShortcuts").last)
        let regex = try NSRegularExpression(pattern: "\"([^\"]*\\\\\\(\\.applicationName\\)[^\"]*)\"")
        let range = NSRange(provider.startIndex..., in: provider)
        let phrases = regex.matches(in: provider, range: range).compactMap { m in
            Range(m.range(at: 1), in: provider).map { String(provider[$0]).replacingOccurrences(of: "\\(.applicationName)", with: "${applicationName}") }
        }
        #expect(phrases.count == 5)
        for p in phrases { #expect(keys.contains(p), "missing in AppShortcuts.xcstrings: \(p)") }
    }
}
