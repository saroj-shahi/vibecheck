import Foundation
import Testing
import VibeCheckShared
@testable import VibeCheck

@Suite struct StatusSnapshotTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func sample(vibe: String = "mid", cpu: Double = 0.3, onAC: Bool = true, names: [String] = ["Chrome"],
                       withCPU: Bool = true, cpuAt: Date = t0) -> StatusSnapshot {
        StatusSnapshot(updatedAt: t0, pid: 42, vibe: vibe,
                       verdict: vibe == "vibing" ? "Your Mac is vibing. Nothing's working hard." : "Kinda mid: memory is getting tight. Chrome grew 2.4 GB in the last hour.",
                       culprit: vibe == "vibing" ? nil : "memory", cpu: cpu, memoryPressure: "warning", swapUsedBytes: 1_000_000_000,
                       thermalState: "nominal", battery: .init(percent: 80, onAC: onAC, minutesLeft: nil),
                       topMemory: names.map { .init(name: $0, bytes: 4_000_000_000, processes: 12, growthBytes: 2_400_000_000, growthMinutes: 60) },
                       topCPU: withCPU ? [.init(name: "Xcode", cpu: 88, processes: 3)] : nil, topCPUAt: withCPU ? cpuAt : nil)
    }

    @Test func roundTrip() throws {
        let s = Self.sample()
        #expect(try StatusSnapshot.decode(s.encoded()) == s)
    }

    @Test func fieldNamesAreStable() throws {
        let object = try JSONSerialization.jsonObject(with: Self.sample().encoded()) as! [String: Any]
        #expect(Set(object.keys) == ["schema", "updatedAt", "pid", "vibe", "verdict", "culprit", "cpu", "memoryPressure",
                                     "swapUsedBytes", "thermalState", "battery", "topMemory", "topCPU", "topCPUAt"])
        #expect(object["schema"] as? Int == 1)
        #expect((object["updatedAt"] as? String)?.hasSuffix("Z") == true)
        let battery = object["battery"] as! [String: Any]
        #expect(Set(battery.keys) == ["percent", "onAC"])
        let mem = (object["topMemory"] as! [[String: Any]])[0]
        #expect(Set(mem.keys) == ["name", "bytes", "processes", "growthBytes", "growthMinutes"])
    }

    @Test func optionalPartsAreOmitted() throws {
        var s = Self.sample(vibe: "vibing", withCPU: false)
        s.battery = nil
        let object = try JSONSerialization.jsonObject(with: s.encoded()) as! [String: Any]
        for key in ["topCPU", "topCPUAt", "battery", "culprit"] { #expect(object[key] == nil) }
    }

    @Test func changeDetection() {
        let base = Self.sample()
        #expect(!base.differsMeaningfully(from: base))
        #expect(Self.sample(cpu: 0.34).differsMeaningfully(from: base) == false)
        #expect(Self.sample(cpu: 0.36).differsMeaningfully(from: base))
        #expect(Self.sample(vibe: "cooked").differsMeaningfully(from: base))
        #expect(Self.sample(onAC: false).differsMeaningfully(from: base))
        #expect(Self.sample(names: ["Safari"]).differsMeaningfully(from: base))
        var verdict = base; verdict.verdict = "other"
        #expect(verdict.differsMeaningfully(from: base))
        var thermal = base; thermal.thermalState = "serious"
        #expect(thermal.differsMeaningfully(from: base))
    }

    @Test func rateLimitAndHeartbeat() {
        let base = Self.sample()
        let changed = Self.sample(vibe: "cooked")
        let t = Self.t0
        #expect(StatusSnapshot.shouldWrite(new: base, last: nil, lastWrite: nil, now: t))
        #expect(!StatusSnapshot.shouldWrite(new: changed, last: base, lastWrite: t, now: t.addingTimeInterval(9)))
        #expect(StatusSnapshot.shouldWrite(new: changed, last: base, lastWrite: t, now: t.addingTimeInterval(10)))
        #expect(!StatusSnapshot.shouldWrite(new: base, last: base, lastWrite: t, now: t.addingTimeInterval(299)))
        #expect(StatusSnapshot.shouldWrite(new: base, last: base, lastWrite: t, now: t.addingTimeInterval(300)))
    }

    @Test func staleness() {
        let s = Self.sample()
        #expect(!s.isStale(now: Self.t0.addingTimeInterval(599)))
        #expect(s.isStale(now: Self.t0.addingTimeInterval(601)))
        #expect(s.isStale(now: Self.t0, isAlive: { _ in false }))
        #expect(!s.isStale(now: Self.t0, isAlive: { $0 == 42 }))
    }

    @Test func staleJSONHasFlag() throws {
        let stale = try JSONSerialization.jsonObject(with: Self.sample().cliJSON(stale: true)) as! [String: Any]
        #expect(stale["stale"] as? Bool == true)
        let fresh = try JSONSerialization.jsonObject(with: Self.sample().cliJSON(stale: false)) as! [String: Any]
        #expect(fresh["stale"] == nil)
    }

    @Test func exitCodes() {
        #expect(Self.sample(vibe: "vibing").moodExitCode == 0)
        #expect(Self.sample(vibe: "mid").moodExitCode == 1)
        #expect(Self.sample(vibe: "cooked").moodExitCode == 2)
    }

    @Test func humanText() {
        #expect(Self.sample().humanStatus() == "Mid: memory is getting tight. Chrome grew 2.4 GB in the last hour.")
        #expect(Self.sample(vibe: "vibing").humanStatus() == "Your Mac is vibing. Nothing's working hard.")
        #expect(Self.sample().humanStatus(stale: true).contains("stale"))
    }

    @Test func culpritFallbackAndFreshness() {
        let s = Self.sample()
        let mem = s.culpritLines(by: "memory", top: 3, now: Self.t0)
        #expect(mem.lines == ["1. Chrome  4.0 GB (12 processes), +2.4 GB in 60 min"] && !mem.usedCPU)
        let cpu = s.culpritLines(by: "cpu", top: 3, now: Self.t0.addingTimeInterval(60))
        #expect(cpu.usedCPU && cpu.lines == ["1. Xcode  88% CPU (3 processes)"])
        let old = s.culpritLines(by: "cpu", top: 3, now: Self.t0.addingTimeInterval(121))
        #expect(!old.usedCPU)
        #expect(Self.sample(withCPU: false).freshTopCPU(now: Self.t0) == nil)
    }

    @Test func thermalNames() {
        #expect(StatusPublisher.thermalName(.nominal) == "nominal")
        #expect(StatusPublisher.thermalName(.critical) == "critical")
    }

    @Test func loadHandlesBadFiles() throws {
        #expect(StatusSnapshot.load(nil) == .missing)
        #expect(StatusSnapshot.load(Data()) == .unreadable)
        #expect(StatusSnapshot.load(Data("{not json".utf8)) == .unreadable)
        #expect(StatusSnapshot.load(Data("{\"schema\": 2}".utf8)) == .unreadable)
        // A newer schema that only added fields still reads.
        var object = try JSONSerialization.jsonObject(with: Self.sample().encoded()) as! [String: Any]
        object["schema"] = 2
        object["newField"] = "x"
        let future = try JSONSerialization.data(withJSONObject: object)
        guard case .snapshot(let loaded) = StatusSnapshot.load(future) else { Issue.record("future schema should load"); return }
        #expect(loaded.schema == 2)
        #expect(loaded.notRunningMessage().hasPrefix("VibeCheck isn't running (last update "))
    }

    @Test func publisherWritesPrivateFiles() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("vc-status-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let url = base.appendingPathComponent("VibeCheck/status.json")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        StatusPublisher.write(Data("{}".utf8), to: url)
        func mode(_ u: URL) -> Int { (try? FileManager.default.attributesOfItem(atPath: u.path)[.posixPermissions] as? Int) ?? -1 }
        #expect(mode(url) == 0o600)
        #expect(mode(url.deletingLastPathComponent()) == 0o700)
        #expect(try Data(contentsOf: url) == Data("{}".utf8))
        // An existing folder keeps its permissions; the file is replaced in place.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.deletingLastPathComponent().path)
        StatusPublisher.write(Data("[]".utf8), to: url)
        #expect(mode(url.deletingLastPathComponent()) == 0o755)
        #expect(mode(url) == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path) == ["status.json"])
    }
}
