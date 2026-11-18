import Foundation
import Testing
@testable import VibeCheck

struct AgentWatchTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func claude(lastActive: Date?) -> AgentSummary {
        var summary = AgentSummary(agent: .claude)
        summary.lastActive = lastActive
        return summary
    }

    @Test func workingMeansAWriteInTheLastThreeMinutes() {
        #expect(AgentWatch.isWorking(claude(lastActive: t0), now: t0.addingTimeInterval(170)))
        #expect(!AgentWatch.isWorking(claude(lastActive: t0), now: t0.addingTimeInterval(190)))
        #expect(!AgentWatch.isWorking(claude(lastActive: nil), now: t0))
        #expect(AgentWatch.anyWorking([claude(lastActive: nil), claude(lastActive: t0)], now: t0))
    }

    @Test func longRunFinishesOnceAfterTheQuietGap() {
        var watch = AgentWatch()
        // Writes every minute for 20 minutes, ticked as the store would see them.
        for minute in 0...20 {
            let at = t0.addingTimeInterval(Double(minute) * 60)
            #expect(watch.update([claude(lastActive: at)], now: at).isEmpty)
        }
        let last = t0.addingTimeInterval(20 * 60)
        #expect(watch.update([claude(lastActive: last)], now: last.addingTimeInterval(120)).isEmpty)
        let done = watch.update([claude(lastActive: last)], now: last.addingTimeInterval(200))
        #expect(done == [AgentWatch.Finished(agent: .claude, duration: 20 * 60)])
        #expect(watch.update([claude(lastActive: last)], now: last.addingTimeInterval(400)).isEmpty)  // only once
    }

    @Test func shortRunsAndPausesUnderTheGapDontNotify() {
        var watch = AgentWatch()
        _ = watch.update([claude(lastActive: t0)], now: t0)
        let fiveMin = t0.addingTimeInterval(300)
        // Quiet for 2.5 min, then back: still the same run.
        _ = watch.update([claude(lastActive: t0.addingTimeInterval(150))], now: t0.addingTimeInterval(150))
        _ = watch.update([claude(lastActive: fiveMin)], now: fiveMin)
        #expect(watch.update([claude(lastActive: fiveMin)], now: fiveMin.addingTimeInterval(200)).isEmpty) // 5 min run
    }

    @Test func messageReadsPlainly() {
        let message = AgentWatch.message(.init(agent: .codex, duration: 84 * 60))
        #expect(message.title == "Codex is done")
        #expect(message.body == "It worked for 1 h 24 min.")
        #expect(AgentWatch.message(.init(agent: .claude, duration: 12 * 60)).body == "It worked for 12 min.")
    }

    @Test func triggerDescriptionNamesTheAgent() {
        #expect(AwakeTriggerAction.description(onPower: false, externalDisplay: false, agentWorking: true)
                == "while an AI agent is working")
        #expect(AwakeTriggerAction.description(onPower: true, externalDisplay: false, agentWorking: true)
                == "while plugged in and an AI agent is working")
    }
}

extension AgentWatchTests {
    @Test func runCutByMidnightIsDroppedQuietly() {
        var watch = AgentWatch()
        for minute in 0...15 {
            let at = t0.addingTimeInterval(Double(minute) * 60)
            _ = watch.update([claude(lastActive: at)], now: at)
        }
        // Logs roll over: no usage today, then a short new run later must not report the old one.
        #expect(watch.update([claude(lastActive: nil)], now: t0.addingTimeInterval(16 * 60)).isEmpty)
        let later = t0.addingTimeInterval(60 * 60)
        _ = watch.update([claude(lastActive: later)], now: later)
        #expect(watch.update([claude(lastActive: later)], now: later.addingTimeInterval(200)).isEmpty)
    }
}
