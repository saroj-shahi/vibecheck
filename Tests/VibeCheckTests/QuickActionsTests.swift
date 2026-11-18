import Testing
@testable import VibeCheck

struct QuickActionsTests {
    @Test func trashLabel() {
        #expect(QuickActionsText.trashLabel(count: 12) == "Trash 12")
        #expect(QuickActionsText.trashLabel(count: 0) == "Trash")
        #expect(QuickActionsText.trashLabel(count: nil) == "Trash")
    }

    @Test func confirmPromptPluralizes() {
        #expect(QuickActionsText.confirmPrompt(count: 12) == "Empty 12 items?")
        #expect(QuickActionsText.confirmPrompt(count: 1) == "Empty 1 item?")
        #expect(QuickActionsText.confirmPrompt(count: nil) == "Empty Trash?")
    }

    @Test func spokenTrash() {
        #expect(QuickActionsText.trashSpoken(count: 12) == "Empty Trash, 12 items")
        #expect(QuickActionsText.trashSpoken(count: 1) == "Empty Trash, 1 item")
    }

    @Test func denialCodeMapsToAutomationMessage() {
        #expect(QuickActionsText.failureMessage(code: -1743) == QuickActionsText.automationDenied)
        #expect(QuickActionsText.automationDenied == "Allow VibeCheck to control System Events in System Settings → Privacy & Security → Automation.")
        #expect(QuickActionsText.failureMessage(code: -1743, target: "Finder").contains("Finder"))
    }

    @Test func otherCodesGetGenericMessage() {
        #expect(QuickActionsText.failureMessage(code: -600) == QuickActionsText.genericFailure)
        #expect(QuickActionsText.failureMessage(code: 0) == QuickActionsText.genericFailure)
    }
}
