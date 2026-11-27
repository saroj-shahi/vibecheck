import Foundation
import Testing
@testable import VibeCheck

struct SettingsNavigationTests {
    @Test func everyModuleHasExactlyOnePage() {
        let modules = SettingsSection.allCases.compactMap { section -> Module? in
            if case .module(let module) = section { return module }
            return nil
        }
        #expect(modules.count == Module.allCases.count)
        #expect(Set(modules) == Set(Module.allCases))
        #expect(Set(SettingsSection.allCases.map(\.id)).count == SettingsSection.allCases.count)   // ids unique
    }

    @Test func groupsAreCoreThenMonitorsThenExtrasThenAbout() {
        let groups = SettingsSection.groups
        #expect(groups.map(\.title) == [nil, "Monitors", "Extras", nil])
        #expect(groups.map(\.id) == ["core", "monitors", "extras", "about"])
        #expect(groups[0].sections == [.general, .menuBar, .keepAwake, .alerts, .clipboard, .shortcuts])
        #expect(groups[2].sections == [.module(.clock), .module(.weather), .module(.todo)])
        #expect(groups[3].sections == [.about])
        #expect(!groups[1].sections.contains(.module(.clock)))
    }

    @Test func sectionRoundTripsByID() {
        for section in SettingsSection.allCases {
            #expect(SettingsSection.from(id: section.id) == section)
        }
        #expect(SettingsSection.from(id: "nonexistent") == nil)
    }

    @Test func searchMatchesTitlesAndKeywords() {
        #expect(SettingsSection.menuBar.matches("notch"))
        #expect(SettingsSection.keepAwake.matches("CAFFEINATE"))
        #expect(SettingsSection.module(.agents).matches("claude limits"))   // every word must match
        #expect(!SettingsSection.module(.agents).matches("claude notch"))
        #expect(SettingsSection.general.matches("export"))
        #expect(SettingsSection.about.matches("coffee"))
        #expect(!SettingsSection.general.matches("weather"))
    }

    @Test func deepSearchFindsHiddenAdvancedAndSubTabControls() {
        let notchHits = SettingsSearchIndex.search("notch")
        #expect(notchHits.contains { $0.id == "menuBar.notch" && $0.disclosureID == "menuBar.advanced" })

        let chimeHits = SettingsSearchIndex.search("chime")
        #expect(chimeHits.contains { $0.id == "clock.chime" && $0.clockTab == .chime && $0.section == .module(.clock) })

        let glassHits = SettingsSearchIndex.search("glass")
        #expect(glassHits.contains { $0.id == "general.deckOpacity" && $0.section == .general })

        let btHits = SettingsSearchIndex.search("airpods")
        #expect(btHits.contains { $0.id == "keepAwake.bluetooth" && $0.section == .keepAwake })

        #expect(SettingsSearchIndex.search("   ").isEmpty)
    }

    @Test @MainActor func routerRevealSwitchesTabExpandsDisclosureAndHighlights() {
        let suite = "SettingsNavigationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let router = SettingsRouter(defaults: defaults)
        let entry = SettingsSearchEntry(
            id: "clock.chime",
            section: .module(.clock),
            title: "Hourly chime",
            breadcrumb: "Date & Time › Hourly Chime",
            keywords: "chime",
            disclosureID: "test.disclosure",
            clockTab: .chime
        )
        router.reveal(entry)
        #expect(router.section == .module(.clock))
        #expect(router.clockTab == .chime)
        #expect(router.expandedDisclosures.contains("test.disclosure"))
        #expect(router.highlightedControlID == "clock.chime")
        // Verify last-viewed section persists cleanly across router instances.
        let restored = SettingsRouter(defaults: defaults)
        #expect(restored.section == .module(.clock))
    }

    @Test func everyAlertMetricBelongsToAModulePage() {
        for metric in AlertMetric.allCases {
            #expect(AlertMetric.metrics(for: metric.module).contains(metric))
            #expect(!metric.shortTitle.isEmpty)
        }
        #expect(AlertMetric.metrics(for: .battery) == [.batteryLevel, .accessoryBattery])
        #expect(AlertMetric.metrics(for: .network).isEmpty)
        #expect(AlertMetric.diskFree.shortTitle == "Disk free")
    }

    @Test func starterAlertsWatchTheRightWay() {
        #expect(AlertRule.starter(for: .cpu).comparison == .above)
        #expect(AlertRule.starter(for: .cpu).threshold == 90)            // from the default rules
        #expect(AlertRule.starter(for: .diskFree).comparison == .below)
        #expect(AlertRule.starter(for: .accessoryBattery).comparison == .below)
        #expect(AlertRule.starter(for: .accessoryBattery).duration == 0)
        #expect(AlertRule.starter(for: .gpu).threshold == 80)
        #expect(AlertRule.starter(for: .cpu).id != AlertRule.defaults[0].id)   // a new rule, not a copy
    }
}
