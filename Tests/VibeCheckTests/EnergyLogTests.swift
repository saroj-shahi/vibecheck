import Foundation
import Testing
@testable import VibeCheck

@MainActor
struct EnergyLogTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("energylog-\(UUID().uuidString)/energy.json")
    }

    private func item(_ pid: Int32, owner: Int32? = nil, name: String = "App", nj: UInt64, start: UInt64 = 1) -> EnergyScanItem {
        EnergyScanItem(pid: pid, owner: owner ?? pid, ownerName: name, nanojoules: nj, start: start)
    }

    private func makeLog(_ url: URL? = nil, now: Date) -> EnergyLog {
        EnergyLog(fileURL: url ?? tempURL(), calendar: calendar, now: now)
    }

    @Test func accumulatesDeltasAndSkipsBaseline() {
        let t0 = date("2026-03-10T10:00:00Z")
        let log = makeLog(now: t0)
        log.record([item(10, nj: 5_000_000_000)], now: t0)
        #expect(log.leaderboard(.today, now: t0).rows.isEmpty)   // first reading is only a baseline
        let t1 = t0.addingTimeInterval(60)
        log.record([item(10, nj: 8_600_000_000)], now: t1)        // +3.6 J
        let board = log.leaderboard(.today, now: t1)
        #expect(board.rows.count == 1)
        #expect(abs(board.total - 3.6) < 1e-9)
        #expect(abs(board.rows[0].share - 1) < 1e-9)
    }

    @Test func pidReuseGivesNoDelta() {
        let t0 = date("2026-03-10T10:00:00Z")
        let log = makeLog(now: t0)
        log.record([item(10, nj: 1_000_000_000, start: 1)], now: t0)
        log.record([item(10, nj: 9_000_000_000, start: 2)], now: t0.addingTimeInterval(60))
        #expect(log.leaderboard(.today, now: t0.addingTimeInterval(60)).rows.isEmpty)
        // A counter that went backwards is also ignored.
        log.record([item(10, nj: 500, start: 2)], now: t0.addingTimeInterval(120))
        #expect(log.leaderboard(.today, now: t0.addingTimeInterval(120)).rows.isEmpty)
    }

    @Test func groupsHelpersUnderResponsibleApp() {
        let t0 = date("2026-03-10T10:00:00Z")
        let log = makeLog(now: t0)
        let first = [item(1, name: "Chrome", nj: 0), item(2, owner: 1, name: "Chrome", nj: 0),
                     item(3, name: "Notes", nj: 0)]
        log.record(first, now: t0, resolveName: { $1 })
        let second = [item(1, name: "Chrome", nj: 2_000_000_000), item(2, owner: 1, name: "Chrome", nj: 4_000_000_000),
                      item(3, name: "Notes", nj: 1_000_000_000)]
        let t1 = t0.addingTimeInterval(60)
        log.record(second, now: t1, resolveName: { $1 })
        let board = log.leaderboard(.today, now: t1)
        #expect(board.rows.map(\.name) == ["Chrome", "Notes"])
        #expect(abs(board.rows[0].joules - 6) < 1e-9)
        #expect(abs(board.rows[0].share - 6.0 / 7.0) < 1e-9)
    }

    @Test func limitsToTopFive() {
        let t0 = date("2026-03-10T10:00:00Z")
        let log = makeLog(now: t0)
        log.record((1...8).map { item(Int32($0), name: "A\($0)", nj: 0) }, now: t0)
        log.record((1...8).map { item(Int32($0), name: "A\($0)", nj: UInt64($0) * 1_000_000_000) },
                   now: t0.addingTimeInterval(60))
        let rows = log.leaderboard(.today, now: t0.addingTimeInterval(60)).rows
        #expect(rows.count == 5)
        #expect(rows.first?.name == "A8")
    }

    @Test func dayRolloverAtMidnightKeepsTodayAndYesterdayOnly() {
        let t0 = date("2026-03-10T23:58:30Z")
        let log = makeLog(now: t0)
        log.record([item(1, nj: 0)], now: t0)
        log.record([item(1, nj: 1_000_000_000)], now: t0.addingTimeInterval(60))   // 23:59:30, day 10
        log.record([item(1, nj: 3_000_000_000)], now: t0.addingTimeInterval(120))  // 00:00:30, day 11
        let now = t0.addingTimeInterval(120)
        #expect(abs(log.leaderboard(.yesterday, now: now).total - 1) < 1e-9)
        #expect(abs(log.leaderboard(.today, now: now).total - 2) < 1e-9)
        // Two days later the oldest day is gone.
        let later = date("2026-03-12T00:10:00Z")
        log.record([item(1, nj: 4_000_000_000)], now: later)
        #expect(log.days.keys.sorted() == ["2026-03-11", "2026-03-12"])
    }

    @Test func persistenceRoundTrip() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let t0 = date("2026-03-10T10:00:00Z")
        let log = makeLog(url, now: t0)
        log.record([item(1, name: "Mail", nj: 0)], now: t0)
        log.record([item(1, name: "Mail", nj: 7_200_000_000)], now: t0.addingTimeInterval(60))
        log.save(at: t0.addingTimeInterval(61))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        let reloaded = makeLog(url, now: t0.addingTimeInterval(120))
        let board = reloaded.leaderboard(.today, now: t0.addingTimeInterval(120))
        #expect(board.rows.map(\.name) == ["Mail"])
        #expect(abs(board.total - 7.2) < 1e-9)
        // Stale days are dropped on load.
        let muchLater = makeLog(url, now: date("2026-03-20T10:00:00Z"))
        #expect(muchLater.days.isEmpty)
    }

    @Test func savesAtMostEveryFiveMinutes() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let t0 = Date()
        let log = EnergyLog(fileURL: url, calendar: calendar, now: t0)
        log.record([item(1, nj: 0)], now: t0.addingTimeInterval(1))
        log.record([item(1, nj: 1_000_000_000)], now: t0.addingTimeInterval(61))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        log.record([item(1, nj: 2_000_000_000)], now: t0.addingTimeInterval(310))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func labels() {
        #expect(EnergyLog.label(wattHours: 0.01) == "<0.1 Wh")
        #expect(EnergyLog.label(wattHours: 1.44) == "1.4 Wh")
    }

    @Test func dueOncePerMinute() {
        let t0 = date("2026-03-10T10:00:00Z")
        let log = makeLog(now: t0)
        #expect(log.isDue(now: t0))
        log.record([], now: t0)
        #expect(!log.isDue(now: t0.addingTimeInterval(30)))
        #expect(log.isDue(now: t0.addingTimeInterval(60)))
    }
}
