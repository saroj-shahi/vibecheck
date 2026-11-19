import Foundation
import Testing
@testable import VibeCheck

@MainActor
struct AlertEngineTests {
    private func engine() -> (AlertEngine, () -> [String]) {
        let engine = AlertEngine()
        var sent: [String] = []
        engine.deliver = { _, body in sent.append(body) }
        return (engine, { sent })
    }

    private let cpuRule = AlertRule(metric: .cpu, comparison: .above, threshold: 90, duration: 30)

    @Test func waitsForDurationBeforeFiring() {
        let (engine, sent) = engine()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        engine.evaluate([cpuRule], now: t0) { _ in 95 }
        engine.evaluate([cpuRule], now: t0 + 20) { _ in 95 }
        #expect(sent().isEmpty)
        engine.evaluate([cpuRule], now: t0 + 30) { _ in 95 }
        #expect(sent().count == 1)
        #expect(sent()[0].contains("above 90%"))
    }

    @Test func dipBelowThresholdResetsTheTimer() {
        let (engine, sent) = engine()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        engine.evaluate([cpuRule], now: t0) { _ in 95 }
        engine.evaluate([cpuRule], now: t0 + 20) { _ in 50 }
        engine.evaluate([cpuRule], now: t0 + 35) { _ in 95 }
        engine.evaluate([cpuRule], now: t0 + 50) { _ in 95 }
        #expect(sent().isEmpty)
    }

    @Test func firesOnceThenRearmsAfterClearingAndCooldown() {
        let (engine, sent) = engine()
        let rule = AlertRule(metric: .temperature, comparison: .above, threshold: 80, duration: 0)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        engine.evaluate([rule], now: t0) { _ in 85 }
        engine.evaluate([rule], now: t0 + 2) { _ in 85 }
        #expect(sent().count == 1)
        // Clears and trips again within the cooldown: no repeat.
        engine.evaluate([rule], now: t0 + 4) { _ in 70 }
        engine.evaluate([rule], now: t0 + 6) { _ in 85 }
        #expect(sent().count == 1)
        // After the cooldown it can fire again.
        engine.evaluate([rule], now: t0 + 400) { _ in 70 }
        engine.evaluate([rule], now: t0 + 402) { _ in 85 }
        #expect(sent().count == 2)
    }

    @Test func belowComparisonAndDisabledRules() {
        let (engine, sent) = engine()
        let battery = AlertRule(metric: .batteryLevel, comparison: .below, threshold: 15, duration: 0)
        var disabled = AlertRule(metric: .cpu, comparison: .above, threshold: 10, duration: 0)
        disabled.enabled = false
        engine.evaluate([battery, disabled]) { $0 == .batteryLevel ? 12 : 99 }
        #expect(sent() == [battery.describe(current: 12)])
    }

    @Test func missingValueNeverFires() {
        let (engine, sent) = engine()
        let gpu = AlertRule(metric: .gpu, comparison: .above, threshold: 1, duration: 0)
        engine.evaluate([gpu]) { _ in nil }
        #expect(sent().isEmpty)
    }
}
