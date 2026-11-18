import Testing
@testable import VibeCheck

@MainActor
struct VerdictTooltipTests {
    private let verdict = "Kinda mid: memory is getting tight."

    @Test func ringAndCombinedItemsCarryTheVerdict() {
        let combined = StatusItemController.verdictText(for: .combined, verdict: verdict)
        #expect(combined?.toolTip == verdict)
        #expect(combined?.accessibility == "VibeCheck. \(verdict)")
        let ring = StatusItemController.verdictText(for: .vibe, verdict: verdict)
        #expect(ring?.toolTip == verdict)
        #expect(ring?.accessibility == "VibeCheck vibe. \(verdict)")
    }

    @Test func moduleAndCupItemsKeepTheirOwnLabels() {
        #expect(StatusItemController.verdictText(for: .single(.cpu), verdict: verdict) == nil)
        #expect(StatusItemController.verdictText(for: .keepAwake, verdict: verdict) == nil)
    }
}

struct RingBadgeTests {
    private let cooked = VibeReport(vibe: .cooked, verdict: "", culprit: .cpu, badge: "CPU 96%")

    @Test func badgeFollowsTheProblemBehindTheVerdict() {
        let input = VibeInput(cpuRecent: 0.96)
        #expect(VibeScore.badge(for: .cooked, input: input) == "CPU 96%")
        #expect(VibeScore.badge(for: .vibing, input: input) == nil)
        #expect(VibeScore.badge(for: .mid, input: VibeInput(memoryPressure: .warning)) == "Memory")
        #expect(VibeScore.badge(for: .mid, input: VibeInput(thermalState: .serious)) == "Throttling")
        #expect(VibeScore.badge(for: .cooked, input: VibeInput(startupDiskFree: 0.03)) == "Disk 3% free")
    }

    @Test func ringShowsTheBadgeOnlyWhenTheCulpritHasNoItem() {
        #expect(VibeItemLabel.shownBadge(cooked, ringShown: true) { _ in false } == "CPU 96%")
        #expect(VibeItemLabel.shownBadge(cooked, ringShown: true) { $0 == .cpu } == nil)
        #expect(VibeItemLabel.shownBadge(cooked, ringShown: false) { _ in false } == nil)
        let vibing = VibeReport(vibe: .vibing, verdict: "")
        #expect(VibeItemLabel.shownBadge(vibing, ringShown: true) { _ in false } == nil)
    }
}

@MainActor
struct BadgeShapeTests {
    @Test func onlyDigitCountChangesTheShape() {
        #expect(StatusItemController.badgeShape("CPU 96%") == StatusItemController.badgeShape("CPU 61%"))
        #expect(StatusItemController.badgeShape("CPU 99%") != StatusItemController.badgeShape("CPU 100%"))
        #expect(StatusItemController.badgeShape(nil) == nil)
    }
}
