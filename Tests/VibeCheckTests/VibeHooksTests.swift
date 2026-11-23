import Testing
import Foundation
@testable import VibeCheck

@MainActor
struct VibeHooksTests {
    nonisolated static let fixed = Date(timeIntervalSince1970: 1_800_000_000)
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static let iso = ISO8601DateFormatter().string(from: t0)

    func json(id: String = "a", label: String = "L", value: String = "v", state: String = "active",
              icon: String? = nil, ttl: Any? = nil, updatedAt: String = VibeHooksTests.iso) -> Data {
        var d: [String: Any] = ["id": id, "label": label, "value": value, "state": state, "updatedAt": updatedAt]
        if let icon { d["icon"] = icon }
        if let ttl { d["ttlSeconds"] = ttl }
        return try! JSONSerialization.data(withJSONObject: d)
    }

    func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vibehooks-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func parsesValid() {
        let h = VibeHooks.parse(json(icon: "bolt.fill", ttl: 60), file: "a.json")
        #expect(h?.id == "a")
        #expect(h?.state == .active)
        #expect(h?.icon == "bolt.fill")
        #expect(h?.ttl == 60)
        #expect(h?.updatedAt == Self.t0)
    }

    @Test func rejectsMissingBadAndWrongTypes() {
        #expect(VibeHooks.parse(Data("nope".utf8), file: "x") == nil)
        #expect(VibeHooks.parse(Data("{\"id\":\"a\"}".utf8), file: "x") == nil)
        #expect(VibeHooks.parse(json(state: "sleeping"), file: "x") == nil)
        #expect(VibeHooks.parse(json(id: ""), file: "x") == nil)
        #expect(VibeHooks.parse(json(updatedAt: "yesterday"), file: "x") == nil)
        #expect(VibeHooks.parse(json(ttl: "soon"), file: "x") == nil)
        #expect(VibeHooks.parse(Data("[1,2]".utf8), file: "x") == nil)
    }

    @Test func badIconFallsBackToNil() {
        #expect(VibeHooks.parse(json(icon: "definitely.not.a.symbol"), file: "x")?.icon == nil)
        #expect(VibeHooks.parse(json(), file: "x")?.icon == nil)
    }

    @Test func clampsTextAndTTL() {
        let h = VibeHooks.parse(json(label: String(repeating: "a", count: 40), value: String(repeating: "b", count: 50)), file: "x")
        #expect(h?.label.count == 24)
        #expect(h?.value.count == 32)
        #expect(h?.ttl == 300)
        #expect(VibeHooks.parse(json(ttl: 1), file: "x")?.ttl == 5)
        #expect(VibeHooks.parse(json(ttl: 10_000_000), file: "x")?.ttl == 86_400)
    }

    @Test func fractionalSecondsDate() {
        #expect(VibeHooks.parse(json(updatedAt: "2027-01-15T08:00:00.250Z"), file: "x") != nil)
    }

    @Test func sortsByUrgencyThenNewest() {
        func hook(_ id: String, _ state: VibeHookState, _ age: TimeInterval) -> VibeHook {
            VibeHook(id: id, label: id, value: "", state: state, icon: nil, updatedAt: Self.t0.addingTimeInterval(-age), ttl: 300, file: id)
        }
        let sorted = VibeHooks.sorted([hook("done", .done, 1), hook("old-active", .active, 50), hook("err", .error, 5),
                                       hook("new-active", .active, 2), hook("need", .needsInput, 90), hook("idle", .idle, 0)])
        #expect(sorted.map(\.id) == ["need", "err", "new-active", "old-active", "idle", "done"])
    }

    @Test func expiryAndNextExpiry() {
        func hook(_ id: String, ttl: TimeInterval) -> VibeHook {
            VibeHook(id: id, label: id, value: "", state: .active, icon: nil, updatedAt: Self.t0, ttl: ttl, file: id)
        }
        let a = hook("a", ttl: 30), b = hook("b", ttl: 100)
        #expect(a.isLive(now: Self.t0.addingTimeInterval(29)))
        #expect(!a.isLive(now: Self.t0.addingTimeInterval(30)))
        #expect(VibeHooks.nextExpiry([b, a], now: Self.t0) == Self.t0.addingTimeInterval(30))
        #expect(VibeHooks.nextExpiry([b, a], now: Self.t0.addingTimeInterval(40)) == Self.t0.addingTimeInterval(100))
        #expect(VibeHooks.nextExpiry([b, a], now: Self.t0.addingTimeInterval(100)) == nil)
        #expect(VibeHooks.nextExpiry([], now: Self.t0) == nil)
    }

    @Test func loadHonoursLimits() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<10 { try json(id: "h\(i)").write(to: dir.appendingPathComponent("h\(i).json")) }
        try Data(repeating: 0x20, count: 5000).write(to: dir.appendingPathComponent("zbig.json"))
        try json(id: "txt").write(to: dir.appendingPathComponent("note.txt"))
        #expect(VibeHooks.load(directory: dir, now: Self.t0).count == 8)

        let dir2 = tempDir()
        defer { try? FileManager.default.removeItem(at: dir2) }
        var big = String(data: json(id: "big"), encoding: .utf8)!
        big.removeLast()
        big += ",\"pad\":\"" + String(repeating: "x", count: 5000) + "\"}"
        try Data(big.utf8).write(to: dir2.appendingPathComponent("zbig.json"))
        try json(id: "ok").write(to: dir2.appendingPathComponent("ok.json"))
        try FileManager.default.createSymbolicLink(at: dir2.appendingPathComponent("link.json"), withDestinationURL: dir2.appendingPathComponent("ok.json"))
        #expect(VibeHooks.load(directory: dir2, now: Self.t0).map(\.id) == ["ok"])
    }

    @Test func missingFolderIsEmptyAndNotCreated() {
        let base = tempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.appendingPathComponent("vibecheck/hooks")
        #expect(VibeHooks.load(directory: dir, now: Self.t0).isEmpty)
        let hooks = VibeHooks(directory: dir, now: { VibeHooksTests.fixed })
        hooks.start()
        #expect(hooks.hooks.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
        hooks.stop()
    }

    @Test func picksUpFolderCreatedLater() async throws {
        let base = tempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let parent = base.appendingPathComponent("vibecheck")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let dir = parent.appendingPathComponent("hooks")
        let hooks = VibeHooks(directory: dir, now: { VibeHooksTests.fixed.addingTimeInterval(10) })
        hooks.start()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try json(id: "late", state: "needs_input").write(to: dir.appendingPathComponent("late.json"))
        for _ in 0..<40 where hooks.hooks.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        #expect(hooks.hooks.map(\.id) == ["late"])
        #expect(hooks.needsInput)
        // In-place edit is noticed too.
        try json(id: "late", state: "done").write(to: dir.appendingPathComponent("late.json"))
        for _ in 0..<40 where hooks.needsInput { try await Task.sleep(for: .milliseconds(100)) }
        #expect(!hooks.needsInput)
        hooks.stop()
    }

    @Test func scriptOutputParses() {
        // Shape written by examples/hooks/*.sh
        let sample = #"{"id":"claude-code","label":"Claude my proj","value":"needs you","state":"needs_input","icon":"hand.raised.fill","updatedAt":"2026-11-23T05:19:45Z","ttlSeconds":3600}"#
        #expect(VibeHooks.parse(Data(sample.utf8), file: "claude-code.json")?.icon == "hand.raised.fill")
    }

    @Test func pulseSettingDefaultsOff() {
        #expect(SettingsBackup.keys.contains("pulseOnAgentNeedsInput"))
    }

    @Test func fifoDoesNotBlock() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(mkfifo(dir.appendingPathComponent("x.json").path, 0o600) == 0)
        #expect(VibeHooks.load(directory: dir, now: Self.t0).isEmpty)
    }

    @Test func duplicateIdsKeepNewest() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let older = ISO8601DateFormatter().string(from: Self.t0.addingTimeInterval(-60))
        try json(id: "same", value: "old", updatedAt: older).write(to: dir.appendingPathComponent("a.json"))
        try json(id: "same", value: "new").write(to: dir.appendingPathComponent("b.json"))
        let loaded = VibeHooks.load(directory: dir, now: Self.t0)
        #expect(loaded.map(\.value) == ["new"])
        #expect(VibeHooks.sorted(loaded + loaded).count == 1)
    }

    @Test func retargetsAsPathGrows() async throws {
        let base = tempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.appendingPathComponent("vibecheck/hooks")
        let hooks = VibeHooks(directory: dir, now: { VibeHooksTests.fixed.addingTimeInterval(10) })
        hooks.start()
        try FileManager.default.createDirectory(at: base.appendingPathComponent("vibecheck"), withIntermediateDirectories: true)
        try await Task.sleep(for: .milliseconds(500))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await Task.sleep(for: .milliseconds(500))
        try json(id: "deep").write(to: dir.appendingPathComponent("deep.json"))
        for _ in 0..<40 where hooks.hooks.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        #expect(hooks.hooks.map(\.id) == ["deep"])
        hooks.stop()
    }
}
