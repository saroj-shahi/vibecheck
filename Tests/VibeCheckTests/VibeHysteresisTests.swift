import Foundation
import Testing
@testable import VibeCheck

/// VC-102: exit thresholds, swapping, fast battery drain, short bursts.
struct VibeHysteresisTests {
    /// Runs samples through the same loop SystemStats uses: held levels fed back, then the tracker.
    private func run(_ inputs: [VibeInput]) -> [Vibe] {
        var tracker = VibeTracker()
        var held: [Module: Vibe] = [:]
        return inputs.map { input in
            var input = input
            input.held = held
            held = VibeScore.held(input)
            return tracker.update(VibeScore.evaluate(input))
        }
    }

    @Test func cpuHoveringAtTheThresholdDoesNotFlicker() {
        // 62%, 58%, 61%, 57%… crosses 60% every sample; once mid, it stays mid above the 50% exit.
        let levels = run([0.62, 0.62, 0.58, 0.61, 0.57, 0.59, 0.56].map { VibeInput(cpuRecent: $0) })
        #expect(levels == [.mid, .mid, .mid, .mid, .mid, .mid, .mid])
    }

    @Test func cpuLeavesMidOnlyBelowTheExitThreshold() {
        let levels = run([0.65, 0.65, 0.49, 0.49].map { VibeInput(cpuRecent: $0) })
        #expect(levels == [.mid, .mid, .mid, .vibing]) // the tracker still wants two samples
    }

    @Test func cookedHoldsDownToItsExitThenDropsToMid() {
        let levels = run([0.9, 0.9, 0.8, 0.8, 0.74, 0.74].map { VibeInput(cpuRecent: $0) })
        #expect(levels == [.cooked, .cooked, .cooked, .cooked, .cooked, .mid])
    }

    @Test func enteringStillNeedsTheEnterThreshold() {
        // 55% from calm is below the 60% enter mark: never mid, even though it's above the exit.
        #expect(run([0.55, 0.55, 0.55].map { VibeInput(cpuRecent: $0) }) == [.vibing, .vibing, .vibing])
    }

    @Test func holdIsPerModule() {
        // Cooked from heat, then heat clears: CPU at 70% must not inherit the cooked hold.
        var first = VibeInput(cpuRecent: 0.7, hottest: 95)
        first.held = [:]
        var second = VibeInput(cpuRecent: 0.7, hottest: 60)
        second.held = VibeScore.held(first)
        #expect(VibeScore.evaluate(second) == .mid)
    }

    @Test func temperatureHasHysteresisToo() {
        let levels = run([82, 82, 78, 79, 75, 75].map { VibeInput(hottest: $0) })
        #expect(levels == [.mid, .mid, .mid, .mid, .mid, .vibing])
    }

    @Test func shortBurstAveragesOutToCalm() {
        // A 10 s compile at 100% inside a 30 s window of 10% idle averages 40%: no change.
        let average = (10 * 1.0 + 20 * 0.1) / 30
        #expect(VibeScore.evaluate(VibeInput(cpuRecent: average)) == .vibing)
    }

    @Test func tightMemoryWithActiveSwappingIsCooked() {
        let swapping = VibeInput(memoryPressure: .warning, swapGrowth: 512 * 1_048_576)
        #expect(VibeScore.evaluate(swapping) == .cooked)
        #expect(VibeScore.badge(for: .cooked, input: swapping) == "Swapping")
        // Old swap that isn't growing doesn't count, and swapping without pressure is fine.
        #expect(VibeScore.evaluate(VibeInput(memoryPressure: .warning, swapGrowth: 0)) == .mid)
        #expect(VibeScore.evaluate(VibeInput(memoryPressure: .normal, swapGrowth: 512 * 1_048_576)) == .vibing)
    }

    @Test func swapGrowthIsNewestMinusOldest() {
        let now = Date()
        #expect(SystemStats.swapGrowth([]) == 0)
        #expect(SystemStats.swapGrowth([(now, 100), (now, 400)]) == 300)
        #expect(SystemStats.swapGrowth([(now, 400), (now, 100)]) == 0)
    }

    @Test func fastDrainOnBatteryIsMid() {
        let draining = VibeInput(batteryOnBattery: 0.6, batteryMinutesLeft: 45)
        #expect(VibeScore.evaluate(draining) == .mid)
        #expect(VibeScore.culprit(for: .mid, input: draining) == .battery)
        #expect(VibeScore.evaluate(VibeInput(batteryOnBattery: 0.6, batteryMinutesLeft: 240)) == .vibing)
        // macOS still estimating (0 or nil): no claim.
        #expect(VibeScore.evaluate(VibeInput(batteryOnBattery: 0.6, batteryMinutesLeft: 0)) == .vibing)
        #expect(VibeScore.evaluate(VibeInput(batteryOnBattery: 0.6, batteryMinutesLeft: nil)) == .vibing)
        // Low charge already says it; no second battery reason.
        let low = VibeInput(batteryOnBattery: 0.15, batteryMinutesLeft: 30)
        #expect(VibeScore.reasons(low).filter { $0.2 == .battery }.count == 1)
    }

    @Test func seriousThermalStateIsAtLeastMid() {
        #expect(VibeScore.evaluate(VibeInput(thermalState: .serious)) >= .mid)
        #expect(VibeScore.evaluate(VibeInput(thermalState: .critical)) == .cooked)
    }
}
