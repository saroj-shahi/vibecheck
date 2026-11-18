import Testing
@testable import VibeCheck

struct VibeTests {
    @Test func calmMacIsVibing() {
        let input = VibeInput(cpuRecent: 0.12, hottest: 45, startupDiskFree: 0.6)
        #expect(VibeScore.evaluate(input) == .vibing)
        #expect(VibeScore.verdict(for: .vibing, input: input, topApp: ("Chrome", 12.4))
                == "Your Mac is vibing. Chrome is the loudest at 12% CPU.")
        #expect(VibeScore.verdict(for: .vibing, input: input, topApp: ("Finder", 1))
                == "Your Mac is vibing. Nothing's working hard.")
    }

    @Test func culpritIsTheModuleBehindTheVerdict() {
        #expect(VibeScore.culprit(for: .vibing, input: VibeInput(cpuRecent: 0.9)) == nil)
        #expect(VibeScore.culprit(for: .cooked, input: VibeInput(cpuRecent: 0.7, hottest: 95)) == .sensors)
        #expect(VibeScore.culprit(for: .mid, input: VibeInput(cpuRecent: 0.7)) == .cpu)
        #expect(VibeScore.culprit(for: .mid, input: VibeInput(memoryPressure: .warning)) == .memory)
        #expect(VibeScore.culprit(for: .mid, input: VibeInput(startupDiskFree: 0.08)) == .disk)
        #expect(VibeScore.culprit(for: .cooked, input: VibeInput(batteryOnBattery: 0.05)) == .battery)
        #expect(VibeScore.culprit(for: .mid, input: VibeInput(thermalState: .serious)) == .sensors)
        // The tracker can lag the input: a mid verdict with nothing left at mid names no one.
        #expect(VibeScore.culprit(for: .mid, input: VibeInput(cpuRecent: 0.1)) == nil)
    }

    @Test func worstProblemDecidesTheVibe() {
        #expect(VibeScore.evaluate(VibeInput(cpuRecent: 0.7)) == .mid)
        #expect(VibeScore.evaluate(VibeInput(cpuRecent: 0.9)) == .cooked)
        #expect(VibeScore.evaluate(VibeInput(memoryPressure: .warning)) == .mid)
        #expect(VibeScore.evaluate(VibeInput(cpuRecent: 0.7, hottest: 95)) == .cooked)
        #expect(VibeScore.evaluate(VibeInput(startupDiskFree: 0.08)) == .mid)
        #expect(VibeScore.evaluate(VibeInput(batteryOnBattery: 0.05)) == .cooked)
        #expect(VibeScore.evaluate(VibeInput(thermalState: .serious)) == .mid)
    }

    @Test func verdictNamesTheWorstReasonFirst() {
        let input = VibeInput(cpuRecent: 0.7, hottest: 94)
        let text = VibeScore.verdict(for: .cooked, input: input, topApp: ("Xcode", 180))
        #expect(text == "Your Mac is cooked: it's running hot at 94 °C. Xcode is the loudest at 180% CPU.")
        #expect(VibeScore.verdict(for: .mid, input: VibeInput(), topApp: nil) == "Kinda mid: things are settling down.")
    }

    @Test func trackerNeedsTwoSamplesToChange() {
        var tracker = VibeTracker()
        #expect(tracker.update(.vibing) == .vibing)     // first sample primes immediately
        #expect(tracker.update(.cooked) == .vibing)     // one spike: ignored
        #expect(tracker.update(.vibing) == .vibing)
        #expect(tracker.update(.mid) == .vibing)
        #expect(tracker.update(.mid) == .mid)           // held for two samples: changes
        #expect(tracker.update(.cooked) == .mid)
        #expect(tracker.update(.vibing) == .mid)        // a different level resets the count
        #expect(tracker.update(.vibing) == .vibing)
    }
}
