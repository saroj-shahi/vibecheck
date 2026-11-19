import Foundation
import Testing
@testable import VibeCheck

/// English is the only language so far; these check that the catalog compiled into the module bundle and that the
/// strings built in code read exactly as the old inline literals did.
struct LocalizationTests {
    @Test func compiledCatalogHasEnglishStrings() throws {
        let url = try #require(Bundle.module.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en"))
        let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
        #expect(table["Cooked"] == "Cooked")
        #expect(table["Your Mac is vibing."] == "Your Mac is vibing.")
        #expect(table["CPU has been pinned at %lld%%"] == "CPU has been pinned at %lld%%")
        #expect(table.count > 400)
    }

    @Test func keysResolveThroughTheModuleBundle() {
        #expect(String(localized: "Kinda mid", bundle: .module) == "Kinda mid")
        let cpu = 96
        #expect(String(localized: "CPU has been pinned at \(cpu)%", bundle: .module) == "CPU has been pinned at 96%")
        #expect(String(localized: "\("Xcode") is the loudest at \(42)% CPU.", bundle: .module) == "Xcode is the loudest at 42% CPU.")
    }

    @Test func verdictSentencesMatchTheOldEnglish() {
        let cooked = VibeScore.verdict(for: .cooked, input: VibeInput(cpuRecent: 0.96), topApp: ("Xcode", 88.4))
        #expect(cooked == "Your Mac is cooked: CPU has been pinned at 96%. Xcode is the loudest at 88% CPU.")
        let mid = VibeScore.verdict(for: .mid, input: VibeInput(startupDiskFree: 0.07), topApp: nil)
        #expect(mid == "Kinda mid: disk is 93% full.")
        let vibing = VibeScore.verdict(for: .vibing, input: VibeInput(), topApp: nil)
        #expect(vibing == "Your Mac is vibing. Nothing's working hard.")
        let settling = VibeScore.verdict(for: .mid, input: VibeInput(), topApp: ("Safari", 12))
        #expect(settling == "Kinda mid: things are settling down. Safari is the loudest at 12% CPU.")
        #expect(VibeScore.badge(for: .cooked, input: VibeInput(hottest: 93.4)) == "93 °C")
        #expect(Vibe.cooked.title == "Cooked" && Vibe.mid.title == "Mid" && Vibe.vibing.title == "Vibing")
    }

    @Test func alertTextMatchesTheOldEnglish() {
        let rule = AlertRule(metric: .cpu, comparison: .above, threshold: 90, duration: 60)
        #expect(rule.describe(current: 96.4) == "CPU usage has been above 90% for 1 min. Now 96%.")
        let battery = AlertRule(metric: .batteryLevel, comparison: .below, threshold: 15, duration: 0)
        #expect(battery.describe(current: 12, detail: "MX Keys") == "Battery level has been below 15%. MX Keys is at 12%.")
        #expect(AlertRule.durationLabel(0) == "instantly")
        #expect(AlertRule.durationLabel(45) == "45 sec")
    }

    @Test func interpolatedNumbersKeepPlainDigits() {
        // Integers that can pass 999 go in as Strings: String(localized:) groups digits ("1,234") otherwise.
        #expect(String(localized: "Fan \(String(1234)) rpm") == "Fan 1234 rpm")
        #expect(AlertRule.durationLabel(1500) == "1500 sec")
        #expect(AgentWatch.message(.init(agent: .claude, duration: 1500 * 60)).body == "It worked for 25 h 0 min.")
        #expect(RateWindow(usedPercent: 1, windowMinutes: 1234, resetsAt: Date()).title == "1234-min limit")
    }

    @Test func notificationAndMenuText() {
        let message = AgentWatch.message(.init(agent: .claude, duration: 24 * 60))
        #expect(message.title == "Claude Code is done" && message.body == "It worked for 24 min.")
        let long = AgentWatch.message(.init(agent: .codex, duration: 135 * 60))
        #expect(long.body == "It worked for 2 h 15 min.")
        #expect(AwakeEndReason.timeUp.message == "Time's up.")
        #expect(QuickActionsText.confirmPrompt(count: 1) == "Empty 1 item?")
        #expect(QuickActionsText.confirmPrompt(count: 3) == "Empty 3 items?")
        #expect(QuickActionsText.trashSpoken(count: 0) == "Empty Trash, nothing to empty")
        #expect(QuickActionsText.trashSpoken(count: 2) == "Empty Trash, 2 items")
    }

    @MainActor @Test func intentAndAccessibilityTextMatchesTheOldEnglish() {
        let stats = SystemStats()
        #expect(StatReading.read(.cpu, stats: stats)?.text == "CPU is at \(Fmt.percent(stats.cpu.total)).")
        #expect(StatReading.read(.download, stats: stats)?.text == "You're offline.")
        #expect(String(localized: "\(12)s ago") == "12s ago")
        #expect(String(localized: "\(String(format: "%.1f", 0.34))%/hr") == "0.3%/hr")
        #expect(String(localized: "\("Chrome"), 5% in use, making your Mac \("cooked")") == "Chrome, 5% in use, making your Mac cooked")
    }
}
