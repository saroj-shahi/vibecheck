import Testing
import Foundation
@testable import VibeCheck

@MainActor
struct CallGuardWiFiTests {
    @Test func callStateDebounces() {
        var state = CallState()
        let seq = [true, true, false, true, false, false, false]
        let changes = seq.map { state.update(detected: $0) }
        #expect(changes == [false, true, false, false, false, false, true])
        #expect(!state.inCall)
    }

    @Test func heavyAppPicksBusiestAndSkipsCallApps() {
        func app(_ id: Int32, _ name: String, _ cpu: Double) -> AppUsage {
            AppUsage(id: id, name: name, cpu: cpu, memory: 0, processCount: 1)
        }
        let apps = [app(10, "zoom.us", 300), app(11, "Xcode", 140), app(12, "Safari", 120), app(13, "Mail", 20), app(99, "VibeCheck", 500)]
        #expect(CallGuard.heavyApp(apps, ownPID: 99)?.name == "Xcode")
        #expect(CallGuard.heavyApp([app(13, "Mail", 20)], ownPID: 99) == nil)
        #expect(CallGuard.warning(name: "Xcode", cpu: 140.4).title == "Xcode is at 140% CPU")
    }

    @Test func alertsHeldDuringCallThenDelivered() {
        let engine = AlertEngine()
        var sent: [String] = []
        var calling = true
        engine.deliver = { title, _ in sent.append(title) }
        engine.inCall = { calling }
        let rules = [AlertRule(metric: .cpu, comparison: .above, threshold: 50, duration: 0),
                     AlertRule(metric: .temperature, comparison: .above, threshold: 50, duration: 0)]
        engine.evaluate(rules, value: { _ in 90 })
        #expect(sent.count == 1 && sent[0].contains("Temperature"))
        #expect(engine.held.count == 1)
        calling = false
        engine.evaluate(rules, value: { _ in 90 })
        #expect(sent.count == 2 && sent[1].contains("CPU"))
        #expect(engine.held.isEmpty)
    }

    @Test func wifiMatching() {
        #expect(WiFiTrigger.matches(current: "Home", wanted: " Home "))
        #expect(!WiFiTrigger.matches(current: "home", wanted: "Home"))
        #expect(!WiFiTrigger.matches(current: nil, wanted: "Home"))
        #expect(!WiFiTrigger.matches(current: "Home", wanted: ""))
    }

    @Test func triggerDescriptionMentionsCallAndWiFi() {
        #expect(AwakeTriggerAction.description(onPower: false, externalDisplay: false, onCall: true) == "while you're on a call")
        #expect(AwakeTriggerAction.description(onPower: false, externalDisplay: false, wifi: "Home") == "while on Wi-Fi Home")
    }
}
