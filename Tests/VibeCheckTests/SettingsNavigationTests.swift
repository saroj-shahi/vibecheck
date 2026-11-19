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

    @Test func groupsAreAppThenMonitorsThenExtras() {
        let groups = SettingsSection.groups
        #expect(groups.map(\.title) == [nil, "Monitors", "Extras"])
        #expect(groups[0].sections.first == .general)
        #expect(groups[2].sections == [.module(.clock), .module(.weather)])
        #expect(!groups[1].sections.contains(.module(.clock)))
    }

    @Test func searchMatchesTitlesAndKeywords() {
        #expect(SettingsSection.menuBar.matches("notch"))
        #expect(SettingsSection.keepAwake.matches("CAFFEINATE"))
        #expect(SettingsSection.module(.agents).matches("claude limits"))   // every word must match
        #expect(!SettingsSection.module(.agents).matches("claude notch"))
        #expect(!SettingsSection.backup.matches("weather"))
    }

    @Test func everyAlertMetricBelongsToAModulePage() {
        for metric in AlertMetric.allCases {
            #expect(AlertMetric.metrics(for: metric.module).contains(metric))
        }
        #expect(AlertMetric.metrics(for: .battery) == [.batteryLevel, .accessoryBattery])
        #expect(AlertMetric.metrics(for: .network).isEmpty)
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
