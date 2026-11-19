import Testing
@testable import VibeCheck

@Suite struct RecoveryCheckTests {
    @Test func recoveryOnlyFromBadToVibing() {
        #expect(RecoveryCheck.isRecovery(from: .cooked, to: .vibing))
        #expect(RecoveryCheck.isRecovery(from: .mid, to: .vibing))
        #expect(!RecoveryCheck.isRecovery(from: nil, to: .vibing))
        #expect(!RecoveryCheck.isRecovery(from: .vibing, to: .vibing))
        #expect(!RecoveryCheck.isRecovery(from: .vibing, to: .cooked))
        #expect(!RecoveryCheck.isRecovery(from: .cooked, to: .mid))
    }

    @Test func hintOnlyAfterUpdate() {
        #expect(!DeckHint.shouldShow(current: "1.2", seen: nil))
        #expect(!DeckHint.shouldShow(current: "1.2", seen: ""))
        #expect(!DeckHint.shouldShow(current: "1.2", seen: "1.2"))
        #expect(DeckHint.shouldShow(current: "1.2", seen: "1.1"))
        #expect(!DeckHint.shouldShow(current: nil, seen: "1.1"))
    }
}
