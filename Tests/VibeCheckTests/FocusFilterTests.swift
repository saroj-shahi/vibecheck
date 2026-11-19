import Testing
@testable import VibeCheck

struct FocusFilterTests {
    @Test func holdCombinesCallAndFocus() {
        let off = FocusFilterState.inactive
        let hold = FocusFilterState(holdAlerts: true, keepDisplayAwake: false)
        #expect(!FocusFilterState.holdAlerts(inCall: false, focus: off))
        #expect(FocusFilterState.holdAlerts(inCall: true, focus: off))
        #expect(FocusFilterState.holdAlerts(inCall: false, focus: hold))
        #expect(FocusFilterState.holdAlerts(inCall: true, focus: hold))
    }

    @Test func keepAwakeFollowsFocus() {
        #expect(!FocusFilterState.keepAwakeActive(focus: .inactive))
        #expect(FocusFilterState.keepAwakeActive(focus: FocusFilterState(holdAlerts: false, keepDisplayAwake: true)))
    }

    @Test func triggerDescriptionMentionsFocus() {
        #expect(AwakeTriggerAction.description(onPower: false, externalDisplay: false, focus: true) == "while a Focus asks for it")
    }
}
