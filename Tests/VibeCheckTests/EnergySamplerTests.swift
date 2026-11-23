import Foundation
import Testing
@testable import VibeCheck

struct EnergySamplerTests {
    private func reading(_ nj: UInt64, start: UInt64 = 100, at time: TimeInterval) -> EnergySampler.Reading {
        .init(nanojoules: nj, start: start, time: time)
    }

    @Test func normalWatts() {
        let w = EnergySampler.watts(previous: reading(1_000_000_000, at: 10), current: reading(4_000_000_000, at: 12))
        #expect(w == 1.5)
    }

    @Test func noValueWithoutHistoryOrOnBadInput() {
        let now = reading(5_000_000_000, at: 20)
        #expect(EnergySampler.watts(previous: nil, current: now) == nil)
        #expect(EnergySampler.watts(previous: reading(9_000_000_000, at: 10), current: now) == nil)   // counter reset
        #expect(EnergySampler.watts(previous: reading(1_000, at: 19.5), current: now) == nil)         // under 1 s
        #expect(EnergySampler.watts(previous: reading(1_000, start: 7, at: 10), current: now) == nil) // pid reused
    }

    @Test func dictionaryWatts() {
        let prev: [Int32: EnergySampler.Reading] = [1: reading(0, at: 0), 2: reading(0, at: 0)]
        let cur: [Int32: EnergySampler.Reading] = [1: reading(2_000_000_000, at: 2), 2: reading(1, start: 5, at: 2), 3: reading(1, at: 2)]
        #expect(EnergySampler.watts(previous: prev, current: cur) == [Int32(1): 1.0])
    }

    @Test func sumsPerApp() {
        let rows = [
            ProcessRow(id: 1, name: "A", cpu: 1, memory: 1, responsible: 1, watts: 1.0),
            ProcessRow(id: 2, name: "A helper", cpu: 1, memory: 1, responsible: 1, watts: 0.5),
            ProcessRow(id: 3, name: "A idle", cpu: 1, memory: 1, responsible: 1),
            ProcessRow(id: 4, name: "B", cpu: 1, memory: 1, responsible: 4),
        ]
        let apps = SystemStats.groupByApp(rows) { _ in nil }
        #expect(apps.first { $0.id == 1 }?.watts == 1.5)
        #expect(apps.first { $0.id == 4 }?.watts == nil)
    }

    @Test func formatting() {
        #expect(EnergySampler.label(nil) == nil)
        #expect(EnergySampler.label(0.09) == nil)
        #expect(EnergySampler.label(0.1) == "~0.1 W")
        #expect(EnergySampler.label(1.24) == "~1.2 W")
        #expect(EnergySampler.label(9.96) == "~10 W")
        #expect(EnergySampler.label(23.4) == "~23 W")
    }

    /// Real counter on this Mac: busy work in this process, two readings 1.1 s apart.
    @Test func realCounterMoves() {
        let pid = ProcessInfo.processInfo.processIdentifier
        func busy() { var x = 0.0; let end = Date().addingTimeInterval(1.1); while Date() < end { x += sin(x) + 1 }; _ = x }
        let a = EnergySampler.read(pids: [pid])[pid]
        busy()
        let b = EnergySampler.read(pids: [pid])[pid]
        let w = EnergySampler.watts(previous: a, current: b!)
        print("ENERGY a=\(a!.nanojoules) b=\(b!.nanojoules) dt=\(b!.time - a!.time) watts=\(String(describing: w))")
        #expect(a != nil && b != nil)
        #expect(w != nil && w! > 0)
    }
}
