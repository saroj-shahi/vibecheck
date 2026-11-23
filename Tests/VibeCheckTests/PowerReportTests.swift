import Foundation
import Testing
@testable import VibeCheck

struct PowerReportTests {
    @Test func wattsFromEachUnit() {
        #expect(PowerReport.watts(delta: 3000, unit: "mJ", seconds: 1) == 3)
        #expect(abs(PowerReport.watts(delta: 3_000_000, unit: "uJ", seconds: 2)! - 1.5) < 1e-9)
        #expect(abs(PowerReport.watts(delta: 2_000_000_000, unit: "nJ", seconds: 1)! - 2) < 1e-9)
        #expect(PowerReport.watts(delta: 5, unit: "J", seconds: 1) == 5)
    }

    @Test func wattsNilPaths() {
        #expect(PowerReport.watts(delta: 10, unit: "furlongs", seconds: 1) == nil)
        #expect(PowerReport.watts(delta: 10, unit: "mJ", seconds: 0) == nil)
        #expect(PowerReport.watts(delta: -1, unit: "mJ", seconds: 1) == nil)
    }

    @Test func reportSumsChannelsAndKeepsMissingNil() {
        let r = PowerReport.report(from: [
            .init(name: "DIE_0_CPU Energy", unit: "mJ", value: 1000),
            .init(name: "DIE_1_CPU Energy", unit: "mJ", value: 500),
            .init(name: "GPU Energy", unit: "nJ", value: 800_000_000),
            .init(name: "DRAM", unit: "mJ", value: 99),
        ], seconds: 1)
        #expect(r.cpu == 1.5)
        #expect(abs(r.gpu! - 0.8) < 1e-9)
        #expect(r.ane == nil)
        #expect(PowerReport.report(from: [], seconds: 1).isEmpty)
    }

    @Test func gpuNotDoubleCounted() {
        let both = PowerReport.report(from: [.init(name: "GPU", unit: "mJ", value: 1000),
                                             .init(name: "GPU Energy", unit: "mJ", value: 1000)], seconds: 1)
        #expect(both.gpu == 1)
        let plain = PowerReport.report(from: [.init(name: "GPU", unit: "mJ", value: 2000)], seconds: 1)
        #expect(plain.gpu == 2)
    }

    @Test func realZeroStaysZero() {
        let r = PowerReport.report(from: [.init(name: "ANE", unit: "mJ", value: 0)], seconds: 2)
        #expect(r.ane == 0)
    }

    @Test func clusterParsing() {
        let map = CoreClusters.parse([
            ["cluster-type": Data([0x45, 0]), "logical-cpu-id": 0],
            ["cluster-type": Data([0x50]), "logical-cpu-id": 1],
            ["cluster-type": "P", "logical-cpu-id": Data([2, 0, 0, 0])],
            ["cluster-type": Data([0x58]), "logical-cpu-id": 3],  // unknown type
            ["logical-cpu-id": 4],                                  // no type
        ])
        #expect(map == [0: "E", 1: "P", 2: "P"])
    }

    @Test func averagesIgnoreOrdering() {
        let map: [Int: Character] = [0: "E", 1: "P", 2: "E", 3: "P"]
        let a = CoreClusters.averages(perCore: [0.1, 0.8, 0.3, 0.6], map: map)
        #expect(abs(a!.e - 0.2) < 1e-9)
        #expect(abs(a!.p - 0.7) < 1e-9)
    }

    @Test func averagesNilWhenMapIncompleteOrOneSided() {
        #expect(CoreClusters.averages(perCore: [0.1, 0.2], map: [0: "E"]) == nil)
        #expect(CoreClusters.averages(perCore: [0.1, 0.2], map: [:]) == nil)
        #expect(CoreClusters.averages(perCore: [0.1, 0.2], map: [0: "P", 1: "P"]) == nil)
        #expect(CoreClusters.averages(perCore: [], map: [0: "P"]) == nil)
    }

    @Test func zeroCPUWhileBusyHidesCPUAndANE() {
        let raw = PowerReport(cpu: 0, gpu: 0.1, ane: 0)
        let r = PowerReport.trusted(raw, cpuBusy: 0.3, zeroed: false)
        #expect(r.zeroed)
        #expect(r.report == PowerReport(cpu: nil, gpu: 0.1, ane: nil))
    }

    @Test func zeroCPUWhileIdleIsKept() {
        let raw = PowerReport(cpu: 0, gpu: 0.1, ane: 0)
        let r = PowerReport.trusted(raw, cpuBusy: 0.04, zeroed: false)
        #expect(!r.zeroed)
        #expect(r.report == raw)
        #expect(!PowerReport.trusted(raw, cpuBusy: nil, zeroed: false).zeroed)
    }

    @Test func nonZeroCPUIsKept() {
        let raw = PowerReport(cpu: 2.5, gpu: 0.1, ane: 0)
        let r = PowerReport.trusted(raw, cpuBusy: 0.9, zeroed: false)
        #expect(!r.zeroed)
        #expect(r.report == raw)
    }

    @Test func zeroedStaysHiddenEvenWhenIdle() {
        let raw = PowerReport(cpu: 0, gpu: 0.2, ane: 0)
        let r = PowerReport.trusted(raw, cpuBusy: 0.0, zeroed: true)
        #expect(r.zeroed)
        #expect(r.report == PowerReport(cpu: nil, gpu: 0.2, ane: nil))
    }
}

struct PowerCeilingTests {
    @Test func implausibleCPUReadingHidesCPUAndANEForGood() {
        let first = PowerReport.trusted(PowerReport(cpu: 186, gpu: 0.3, ane: 0), cpuBusy: 0.2, zeroed: false)
        #expect(first.zeroed)
        #expect(first.report == PowerReport(cpu: nil, gpu: 0.3, ane: nil))
        let later = PowerReport.trusted(PowerReport(cpu: 4, gpu: 0.3, ane: 0), cpuBusy: 0.2, zeroed: first.zeroed)
        #expect(later.report.cpu == nil)
    }

    @Test func implausibleGPUReadingIsDroppedOnce() {
        let r = PowerReport.trusted(PowerReport(cpu: 5, gpu: 900, ane: 0.1), cpuBusy: 0.3, zeroed: false)
        #expect(r.report == PowerReport(cpu: 5, gpu: nil, ane: 0.1))
        #expect(!r.zeroed)
    }
}
