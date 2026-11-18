import Foundation
import Testing
@testable import VibeCheck

@MainActor
struct HistoryStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vibecheck-test-\(UUID().uuidString).json")
    }

    @Test func averagesSamplesIntoBuckets() {
        let store = HistoryStore(fileURL: tempURL())
        let t0 = Date(timeIntervalSince1970: 6_000_000) // on a 6s and 144s boundary
        store.record([.cpu: 0.2], at: t0)
        store.record([.cpu: 0.4], at: t0 + 2)
        store.record([.cpu: 0.6], at: t0 + 4)
        #expect(store.points(.cpu, .hour).isEmpty) // bucket still open
        store.record([.cpu: 1.0], at: t0 + 6)      // closes the first 6s bucket
        let hour = store.points(.cpu, .hour)
        #expect(hour.count == 1)
        #expect(abs(hour[0].v - 0.4) < 1e-9)
        #expect(hour[0].t == t0.timeIntervalSince1970)
        #expect(store.points(.cpu, .day).isEmpty)  // 144s bucket still open
    }

    @Test func dropsPointsOlderThanTheRange() {
        let store = HistoryStore(fileURL: tempURL())
        let t0 = Date(timeIntervalSince1970: 6_000_000)
        store.record([.memory: 0.5], at: t0)
        store.record([.memory: 0.5], at: t0 + 6)
        store.record([.memory: 0.5], at: t0 + 3_700)  // more than an hour later
        store.record([.memory: 0.5], at: t0 + 3_706)
        let hour = store.points(.memory, .hour)
        #expect(hour.allSatisfy { $0.t >= t0.timeIntervalSince1970 + 3_706 - 3_600 })
    }

    @Test func savesAndReloads() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date()
        let store = HistoryStore(fileURL: url)
        store.record([.download: 1000], at: now - 12)
        store.record([.download: 3000], at: now - 6)
        store.record([.download: 3000], at: now)
        store.save()
        let reloaded = HistoryStore(fileURL: url)
        #expect(reloaded.points(.download, .hour).count == store.points(.download, .hour).count)
        #expect(!reloaded.points(.download, .hour).isEmpty)
    }
}
