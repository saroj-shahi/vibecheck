import Foundation
import Testing
@testable import VibeCheck

@MainActor
struct SmartAlertTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// One sample a minute for `minutes`, footprint from `footprint(minuteIndex)`.
    private func samples(minutes: Int, _ footprint: (Int) -> Double) -> [AppMemorySample] {
        (0...minutes).map { AppMemorySample(date: t0.addingTimeInterval(Double($0) * 60), footprint: footprint($0), processCount: 1) }
    }
    private func tracks(_ s: [AppMemorySample], name: String = "Chrome") -> [AppMemoryKey: AppMemoryTrack] {
        [AppMemoryKey(pid: 1, startTime: 1): AppMemoryTrack(name: name, samples: s)]
    }
    private func end(_ minutes: Int) -> Date { t0.addingTimeInterval(Double(minutes) * 60) }
    private func eval(_ state: inout SmartAlertState, _ input: SmartAlertInput, _ toggles: SmartAlertToggles? = nil, at now: Date) -> [SmartAlert] {
        state.evaluate(input, enabled: toggles ?? on, now: now)
    }
    private func allow(_ l: inout AlertRateLimiter, _ k: SmartAlertKind, _ c: String?, _ offset: TimeInterval) -> Bool {
        l.allow(k, culprit: c, now: t0.addingTimeInterval(offset))
    }
    private let on = SmartAlertToggles(memoryLeak: true, throttling: true, slowCharger: true)

    // MARK: Memory

    @Test func stillClimbingDetection() {
        #expect(SmartAlertState.isStillClimbing(samples(minutes: 60) { Double($0) * 1e7 }))
        #expect(SmartAlertState.isStillClimbing(samples(minutes: 60) { _ in 5e9 }))   // flat counts as non-decreasing
        // Dropped in the last 10 minutes.
        #expect(!SmartAlertState.isStillClimbing(samples(minutes: 60) { $0 > 52 ? 1e9 : Double($0) * 1e7 + 2e9 }))
        // Too little history for the 30 minute look-back.
        #expect(!SmartAlertState.isStillClimbing(samples(minutes: 20) { Double($0) * 1e7 }))
    }

    @Test func leakFiresWithText() {
        var state = SmartAlertState()
        let s = samples(minutes: 60) { 1e9 + Double($0) * 3e7 }   // +1.8 GB over the hour
        let alerts = state.evaluate(SmartAlertInput(memoryTracks: tracks(s)), enabled: on, now: end(60))
        #expect(alerts.count == 1)
        #expect(alerts.first?.culprit == "Chrome")
        #expect(alerts.first?.body == "Chrome has grown \(Fmt.bytes(1.8e9)) in the last hour and is still climbing.")
    }

    @Test func leakNeedsGrowthHistoryAndClimb() {
        var state = SmartAlertState()
        func run(_ s: [AppMemorySample], _ minutes: Int) -> Int {
            state = SmartAlertState()
            return state.evaluate(SmartAlertInput(memoryTracks: tracks(s)), enabled: on, now: end(minutes)).count
        }
        #expect(run(samples(minutes: 60) { Double($0) * 1e6 }, 60) == 0)               // grew only 60 MB
        #expect(run(samples(minutes: 30) { Double($0) * 5e7 }, 30) == 0)               // 1.5 GB but only 30 min
        #expect(run(samples(minutes: 60) { $0 > 52 ? 1e9 : Double($0) * 5e7 }, 60) == 0) // fell back: not climbing
        #expect(run(samples(minutes: 60) { 1e9 + Double($0) * 3e7 }, 60) == 1)
        // Switched off.
        state = SmartAlertState()
        let offResult = eval(&state, SmartAlertInput(memoryTracks: tracks(samples(minutes: 60) { 1e9 + Double($0) * 3e7 })), SmartAlertToggles(), at: end(60))
        #expect(offResult.isEmpty)
    }

    // MARK: Throttling and charger

    /// Evaluates every 10 s from `from` to `to` (inclusive), like ticks, and returns everything fired.
    private func run(_ state: inout SmartAlertState, _ input: SmartAlertInput, from: Double, to: Double) -> [SmartAlert] {
        stride(from: from, through: to, by: 10).flatMap { eval(&state, input, at: t0.addingTimeInterval($0)) }
    }

    @Test func throttlingNeedsFiveMinutesAndResets() {
        var state = SmartAlertState()
        let hot = SmartAlertInput(thermalSerious: true), cool = SmartAlertInput()
        #expect(run(&state, hot, from: 0, to: 240).isEmpty)
        // A break resets the clock.
        #expect(eval(&state, cool, at: t0.addingTimeInterval(250)).isEmpty)
        #expect(run(&state, hot, from: 260, to: 550).isEmpty)
        let fired = eval(&state, hot, at: t0.addingTimeInterval(560))
        #expect(fired.map(\.kind) == [.throttling])
        #expect(fired.first?.body == "macOS has been throttling your Mac for 5 min to cool it down.")
    }

    @Test func slowChargerNeedsFiveMinutesAndResets() {
        var state = SmartAlertState()
        let slow = SmartAlertInput(slowChargerWatts: 20), fine = SmartAlertInput()
        #expect(run(&state, slow, from: 0, to: 190).isEmpty)
        #expect(eval(&state, fine, at: t0.addingTimeInterval(200)).isEmpty)
        #expect(run(&state, slow, from: 210, to: 500).isEmpty)
        let fired = eval(&state, slow, at: t0.addingTimeInterval(510))
        #expect(fired.first?.body == "Your 20 W charger can't keep up. The battery is still draining while plugged in.")
    }

    @Test func switchedOffAlertsNeverFire() {
        var state = SmartAlertState()
        let input = SmartAlertInput(thermalSerious: true, slowChargerWatts: 20)
        _ = state.evaluate(input, enabled: SmartAlertToggles(), now: t0)
        let later = eval(&state, input, SmartAlertToggles(), at: t0.addingTimeInterval(900))
        #expect(later.isEmpty)
    }

    // MARK: Limiter

    @Test func limiterAllowsOnePerKindAndCulpritPerTwoHours() {
        var limiter = AlertRateLimiter()
        #expect(allow(&limiter, .memoryLeak, "Chrome", 0))
        #expect(!allow(&limiter, .memoryLeak, "Chrome", 3600))
        #expect(allow(&limiter, .memoryLeak, "Safari", 3600))
        #expect(allow(&limiter, .throttling, nil, 3600))
        #expect(!allow(&limiter, .throttling, nil, 7000))
        #expect(allow(&limiter, .memoryLeak, "Chrome", 7200))
    }

    @Test func sustainedThrottlingAlertsOncePerTwoHours() {
        var state = SmartAlertState()
        let hot = SmartAlertInput(thermalSerious: true)
        var count = 0
        for second in stride(from: 0, through: 3 * 3600, by: 60) {
            count += state.evaluate(hot, enabled: on, now: t0.addingTimeInterval(Double(second))).count
        }
        #expect(count == 2)   // at 5 min, then again after 2 hours
    }

    // MARK: Engine delivery

    @Test func engineHoldsDuringCallsAndLogs() {
        let engine = AlertEngine()
        var sent: [String] = []
        engine.deliver = { title, _ in sent.append(title) }
        var calling = true
        engine.inCall = { calling }
        let hot = SmartAlertInput(thermalSerious: true)
        let toggles = SmartAlertToggles(throttling: true)
        for second in stride(from: 0.0, through: 300, by: 10) {
            engine.evaluateSmart(hot, enabled: toggles, now: t0.addingTimeInterval(second))
        }
        #expect(sent.isEmpty)
        #expect(engine.held.count == 1)
        calling = false
        engine.evaluateSmart(hot, enabled: toggles, now: t0.addingTimeInterval(310))
        #expect(sent == ["VibeCheck · Throttling"])
    }

    // MARK: Device refresh policy

    @Test func refreshPolicy() {
        typealias P = DeviceRefreshPolicy
        #expect(P.mode(viewOpen: false, alertRuleOn: false, eventsAvailable: true) == .off)
        #expect(P.mode(viewOpen: false, alertRuleOn: false, eventsAvailable: false) == .off)
        #expect(P.mode(viewOpen: true, alertRuleOn: false, eventsAvailable: true) == .eventOnly)
        #expect(P.mode(viewOpen: true, alertRuleOn: false, eventsAvailable: false) == .poll(60))
        #expect(P.mode(viewOpen: false, alertRuleOn: true, eventsAvailable: true) == .poll(600))
        #expect(P.mode(viewOpen: true, alertRuleOn: true, eventsAvailable: true) == .poll(600))
        #expect(P.mode(viewOpen: false, alertRuleOn: true, eventsAvailable: false) == .poll(60))
    }

    @Test func pollDueOnlyForPollModes() {
        typealias P = DeviceRefreshPolicy
        #expect(!P.pollDue(.eventOnly, lastFetch: nil, now: t0))
        #expect(!P.pollDue(.off, lastFetch: nil, now: t0))
        #expect(P.pollDue(.poll(600), lastFetch: nil, now: t0))
        #expect(!P.pollDue(.poll(600), lastFetch: t0, now: t0.addingTimeInterval(599)))
        #expect(P.pollDue(.poll(600), lastFetch: t0, now: t0.addingTimeInterval(600)))
    }
}

struct ConditionTimerGapTests {
    @Test func aGapLongerThanThirtySecondsRestartsTheCount() {
        var timer = ConditionTimer()
        let t0 = Date()
        _ = timer.update(true, now: t0)
        #expect(timer.update(true, now: t0.addingTimeInterval(10)) == 10)
        // Asleep for an hour while hot: on wake the count starts again, it doesn't claim 60 min.
        #expect(timer.update(true, now: t0.addingTimeInterval(3610)) == 0)
        #expect(timer.update(true, now: t0.addingTimeInterval(3620)) == 10)
    }
}
