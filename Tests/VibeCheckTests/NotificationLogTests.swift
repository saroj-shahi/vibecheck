import Foundation
import Testing
@testable import VibeCheck

@MainActor
struct NotificationLogTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func keepsTheNewestTwentyNewestFirst() {
        let log = NotificationLog(fileURL: nil)
        for i in 0..<25 { log.record(.alert, title: "T\(i)", body: "B\(i)", at: start.addingTimeInterval(Double(i))) }
        #expect(log.entries.count == 20)
        #expect(log.entries.first?.title == "T24")
        #expect(log.entries.last?.title == "T5")
    }

    @Test func unseenCountsOnlyNewerThanLastLook() {
        let log = NotificationLog(fileURL: nil)
        log.record(.alert, title: "a", body: "", at: start)
        log.record(.keepAwake, title: "b", body: "", at: start.addingTimeInterval(60))
        #expect(log.unseenCount == 2)
        log.markAllSeen(at: start.addingTimeInterval(120))
        #expect(log.unseenCount == 0)
        log.record(.alert, title: "c", body: "", at: start.addingTimeInterval(180))
        #expect(log.unseenCount == 1)
        log.clear()
        #expect(log.entries.isEmpty && log.unseenCount == 0)
    }

    @Test func survivesARestart() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "vibecheck-notifications-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = NotificationLog(fileURL: url)
        log.record(.keepAwake, title: "Keep awake ended", body: "Time's up.", at: start)
        log.markAllSeen(at: start.addingTimeInterval(1))
        log.record(.alert, title: "VibeCheck · CPU", body: "CPU usage is above 90%", at: start.addingTimeInterval(5))
        let reloaded = NotificationLog(fileURL: url)
        #expect(reloaded.entries == log.entries)
        #expect(reloaded.unseenCount == 1)
    }

    @Test func firedAlertsAreRecorded() {
        let engine = AlertEngine()
        engine.deliver = { _, _ in }
        let log = NotificationLog(fileURL: nil)
        engine.log = log
        let rule = AlertRule(metric: .temperature, comparison: .above, threshold: 80, duration: 0)
        engine.evaluate([rule], now: start) { _ in 92 }
        #expect(log.entries.count == 1)
        #expect(log.entries.first?.kind == .alert)
        #expect(log.entries.first?.title == "VibeCheck · \(AlertMetric.temperature.title)")
        engine.evaluate([rule], now: start.addingTimeInterval(5)) { _ in 93 } // still tripped: no repeat
        #expect(log.entries.count == 1)
    }
}
