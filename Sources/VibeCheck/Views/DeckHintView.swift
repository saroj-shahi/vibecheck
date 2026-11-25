import SwiftUI

/// One dismissible line on the deck home, shown once per app version (stored by CFBundleShortVersionString).
enum DeckHint {
    static let seenKey = "deckHintSeenVersion"
    static var text: String { String(localized: "New in 1.9: live Antigravity plan limits via agy CLI and a local 5-hour window estimate.") }

    static var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Shown only after an update: a version was stored before and it differs. First run (nothing stored)
    /// shows nothing and just stores the version. Pure, for tests.
    nonisolated static func shouldShow(current: String?, seen: String?) -> Bool {
        guard let current, !current.isEmpty, let seen, !seen.isEmpty else { return false }
        return current != seen
    }
}

struct DeckHintView: View {
    @AppStorage(DeckHint.seenKey) private var seen = ""
    @State private var dismissed = false

    var body: some View {
        Group { hint }
            .onAppear { if seen.isEmpty { seen = DeckHint.currentVersion ?? "" } }
    }

    @ViewBuilder private var hint: some View {
        if !dismissed, DeckHint.shouldShow(current: DeckHint.currentVersion, seen: seen) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lightbulb").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(DeckHint.text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Dismiss")
                .accessibilityLabel("Dismiss tip")
            }
            .padding(.horizontal, 4)
            .transition(.opacity)
            .onDisappear { if !dismissed { seen = DeckHint.currentVersion ?? "" } }
        }
    }

    private func dismiss() {
        seen = DeckHint.currentVersion ?? ""
        withAnimation(Deck.animation) { dismissed = true }
    }
}
