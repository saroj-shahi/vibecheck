import AppKit

/// Asks once, a couple of days after VibeCheck is first opened, for a star on GitHub. Whatever the answer
/// (or a dismissal), it never asks again.
@MainActor
final class StarPrompt {
    static let shared = StarPrompt()

    var defaults: UserDefaults = .standard
    var now: () -> Date = { Date() }
    enum Choice { case star, support, later }
    /// Shows the modal and returns the owner's answer; replaceable in tests.
    var present: @MainActor () -> Choice = { StarPrompt.runAlert() }
    var openURL: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    private var loop: Task<Void, Never>?

    static let firstSeenKey = "starPromptFirstSeen", shownKey = "starPromptShown"
    nonisolated static let delay: TimeInterval = 2 * 24 * 3600
    nonisolated static let repoURL = URL(string: "https://github.com/saroj-shahi/vibecheck")!
    nonisolated static let supportURL = URL(string: "https://buymeacoffee.com/sarojshahi")!

    /// Records the first launch, then looks every hour whether it's time.
    func start() {
        guard loop == nil else { return }
        if defaults.object(forKey: Self.firstSeenKey) == nil { defaults.set(now(), forKey: Self.firstSeenKey) }
        loop = Task { [weak self] in
            // Not in the middle of launching: give the menu bar a few minutes first.
            try? await Task.sleep(for: .seconds(300))
            while !Task.isCancelled {
                self?.showIfDue()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func showIfDue() {
        let firstSeen = defaults.object(forKey: Self.firstSeenKey) as? Date
        guard Self.isDue(firstSeen: firstSeen, shown: defaults.bool(forKey: Self.shownKey), now: now()) else { return }
        // Mark it first so a crash or quit mid-alert can't bring it back.
        defaults.set(true, forKey: Self.shownKey)
        loop?.cancel()
        switch present() {
        case .star: openURL(Self.repoURL)
        case .support: openURL(Self.supportURL)
        case .later: break
        }
    }

    nonisolated static func isDue(firstSeen: Date?, shown: Bool, now: Date) -> Bool {
        guard !shown, let firstSeen else { return false }
        return now.timeIntervalSince(firstSeen) >= delay
    }

    private static func runAlert() -> Choice {
        let alert = NSAlert()
        alert.messageText = String(localized: "Enjoying VibeCheck?")
        alert.informativeText = String(localized: "If it's been useful, a star on GitHub helps other people find it, and a coffee keeps it going. This is the only time we'll ask.")
        alert.addButton(withTitle: String(localized: "Star on GitHub"))
        alert.addButton(withTitle: String(localized: "Buy Me a Coffee"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .star
        case .alertSecondButtonReturn: return .support
        default: return .later
        }
    }
}
