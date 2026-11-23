import Testing
@testable import VibeCheck

@Suite("On-device explainer")
struct OnDeviceExplainerTests {
    private func facts() -> ExplainFacts {
        ExplainFacts(vibe: "Mid", verdict: "Kinda mid: memory is tight. Google Chrome grew 2.4 GB in the last hour.",
                     cpuAverage: 0.424, memoryPressure: "Warning", swapGrowing: true, thermal: "nominal",
                     onBattery: true, batteryMinutes: 95,
                     topCPU: [("Google Chrome", 38.4), ("Xcode", 22), ("Slack", 4), ("Mail", 1)],
                     memoryApp: ("Google Chrome", 6.1 * 1_073_741_824, 34, 2.4 * 1_073_741_824, 58))
    }

    @Test func factsStringIsCompact() {
        let text = OnDeviceExplainer.factsString(facts())
        #expect(text.contains("Vibe: Mid."))
        #expect(text.contains("CPU 30 s average: 42%."))
        #expect(text.contains("Memory pressure: warning. Swap is growing. Thermal state: nominal."))
        #expect(text.contains("On battery, 95 minutes left."))
        #expect(text.contains("Top apps by CPU: Google Chrome 38%, Xcode 22%, Slack 4%."))
        #expect(!text.contains("Mail 1%"))
        #expect(text.contains("Top memory app: Google Chrome, 6.1 GB, 34 processes, grew 2.4 GB in the last 58 minutes."))
    }

    @Test func factsStringWithoutOptionals() {
        var f = facts()
        f.onBattery = false; f.topCPU = []; f.memoryApp = nil; f.swapGrowing = false
        let text = OnDeviceExplainer.factsString(f)
        #expect(text.contains("Plugged in or no battery."))
        #expect(text.contains("Swap is not growing"))
        #expect(!text.contains("Top apps"))
        #expect(!text.contains("Top memory"))
    }

    @Test func postCheckAcceptsFactsOnly() {
        let f = OnDeviceExplainer.factsString(facts())
        #expect(OnDeviceExplainer.passesPostCheck(["Chrome is using memory", "Google Chrome grew 2.4 GB.", "Quit Google Chrome"], facts: f))
        #expect(OnDeviceExplainer.passesPostCheck(["CPU is at 42%", "Busy", "Wait"], facts: f))
    }

    @Test func postCheckRejectsInventedNumbersAndApps() {
        let f = OnDeviceExplainer.factsString(facts())
        #expect(!OnDeviceExplainer.passesPostCheck(["Memory at 9 GB", "x", "y"], facts: f))
        #expect(!OnDeviceExplainer.passesPostCheck(["CPU at 88%", "x", "y"], facts: f))
        #expect(!OnDeviceExplainer.passesPostCheck(["Busy", "Spotify is heavy", "Quit it"], facts: f))
    }

    @Test func postCheckNumbersUseToleranceAndBoundaries() {
        func ok(_ text: String, _ facts: String) -> Bool { OnDeviceExplainer.passesPostCheck([text], facts: facts) }
        #expect(ok("It grew 1 GB", "Top memory app: X, 1.0 GB."))
        #expect(!ok("CPU at 10%", "CPU 30 s average: 110%."))
        #expect(ok("It grew 2.4 GB", "grew 2.4 GB in the last 58 minutes"))
        #expect(!ok("It uses 9 GB", "grew 2.4 GB, using 6.1 GB"))
        #expect(ok("CPU about 42%", "CPU 30 s average: 42%."))
        #expect(ok("About 58 minutes", "in the last 58 minutes"))
        #expect(!ok("About 30 min", "in the last 58 minutes"))
        #expect(!ok("42 GB", "CPU 42%"))   // units must be compatible
    }

    @Test func postCheckAppNamesMatchWholeWordsOnly() {
        let f = "Top apps by CPU: Google Chrome 38%."
        #expect(OnDeviceExplainer.passesPostCheck(["Check your notes and music", "Teamsters wait"], facts: f))
        #expect(!OnDeviceExplainer.passesPostCheck(["Quit Slack"], facts: f))
        #expect(!OnDeviceExplainer.passesPostCheck(["Close Zoom."], facts: f))
        #expect(OnDeviceExplainer.passesPostCheck(["Quit Google Chrome"], facts: f))
    }

    @Test func availabilityMapsToToggleState() {
        func state(_ a: Bool, _ r: ExplainUnavailableReason?) -> ExplainToggleState {
            OnDeviceExplainer.toggleState(for: OnDeviceExplainer.mapAvailability(available: a, reason: r))
        }
        #expect(state(true, nil) == .enabled)
        #expect(state(false, .deviceNotEligible) == .hidden)
        #expect(state(false, .other) == .hidden)
        if case .disabled(let reason) = state(false, .appleIntelligenceOff) { #expect(!reason.isEmpty) } else { Issue.record("expected disabled") }
        if case .disabled(let reason) = state(false, .modelNotReady) { #expect(!reason.isEmpty) } else { Issue.record("expected disabled") }
    }
}
