import Foundation
import Testing
@testable import VibeCheck
import VibeCheckShared

struct WidgetSnapshotTests {
    @Test func downsampleAveragesInOrder() {
        #expect(WidgetSnapshot.downsample([1, 2, 3], to: 5) == [1, 2, 3])
        #expect(WidgetSnapshot.downsample([0, 2, 4, 6], to: 2) == [1, 5])
        let many = (0..<600).map(Double.init)
        let small = WidgetSnapshot.downsample(many)
        #expect(small.count == WidgetSnapshot.maxPoints)
        #expect(small == small.sorted())
        #expect(small.first == 4.5 && small.last == 594.5)
    }

    @Test func roundTripsThroughAFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-\(UUID().uuidString)/snapshot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var snapshot = WidgetSnapshot.placeholder
        snapshot.date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(WidgetShared.write(snapshot, to: url))
        #expect(WidgetShared.read(from: url) == snapshot)
        #expect(WidgetShared.read(from: url.appendingPathExtension("missing")) == nil)
    }

    @Test func staleAfterFifteenMinutes() {
        var s = WidgetSnapshot.placeholder
        s.date = Date(timeIntervalSince1970: 1_000)
        #expect(!s.isStale(at: Date(timeIntervalSince1970: 1_000 + 14 * 60)))
        #expect(s.isStale(at: Date(timeIntervalSince1970: 1_000 + 16 * 60)))
    }

    @Test func snapshotKeepsTheLastHourClamped() {
        let now = Date(timeIntervalSince1970: 100_000)
        let points = [HistoryPoint(t: now.timeIntervalSince1970 - 4_000, v: 0.9),
                      HistoryPoint(t: now.timeIntervalSince1970 - 60, v: 1.4),
                      HistoryPoint(t: now.timeIntervalSince1970 - 6, v: 0.2)]
        let report = VibeReport(vibe: .mid, verdict: "Your Mac is mid", culprit: .cpu, badge: "CPU 70%")
        let s = WidgetPublisher.snapshot(report: report, cpu: 0.7, memory: 0.4, cpuHour: points, memoryHour: [],
                                         now: now)
        #expect(s.vibe == 1 && s.verdict == "Your Mac is mid" && s.vibeTitle == "Mid")
        #expect(s.cpuHour == [1, 0.2])
        #expect(s.memoryHour.isEmpty)
        #expect(s.date == now)
    }
}
