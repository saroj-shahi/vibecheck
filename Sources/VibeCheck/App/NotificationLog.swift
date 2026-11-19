import Foundation
import Observation

/// One notification VibeCheck sent: an alert firing or a keep-awake session ending.
struct LoggedNotification: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case alert, keepAwake, agent }
    var id = UUID()
    var date: Date
    var kind: Kind
    var title: String
    var body: String

    var symbol: String {
        switch kind {
        case .alert: "bell.badge"
        case .keepAwake: "cup.and.saucer"
        case .agent: "sparkles"
        }
    }
}

/// The last 20 notifications, newest first, saved to Application Support so they survive restarts.
/// Shown in the deck behind the bell, with a dot for ones not seen yet.
@Observable
@MainActor
final class NotificationLog {
    static let limit = 20
    static let shared = NotificationLog()

    private(set) var entries: [LoggedNotification] = []
    /// Everything at or before this date has been seen in the deck.
    private(set) var seenUntil: Date = .distantPast
    @ObservationIgnored private let fileURL: URL?

    private struct Stored: Codable {
        var entries: [LoggedNotification]
        var seenUntil: Date
    }

    nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "VibeCheck/notifications.json")
    }

    /// `fileURL` nil keeps everything in memory (tests).
    init(fileURL: URL? = NotificationLog.defaultFileURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            entries = Array(stored.entries.sorted { $0.date > $1.date }.prefix(Self.limit))
            seenUntil = stored.seenUntil
        }
    }

    var unseenCount: Int { entries.filter { $0.date > seenUntil }.count }

    func record(_ kind: LoggedNotification.Kind, title: String, body: String, at date: Date = Date()) {
        entries.insert(LoggedNotification(date: date, kind: kind, title: title, body: body), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
    }

    func markAllSeen(at date: Date = Date()) {
        guard unseenCount > 0 else { return }
        seenUntil = max(date, entries.first?.date ?? date)
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Stored(entries: entries, seenUntil: seenUntil)).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("%@", "VibeCheck: couldn't save notification history: \(error.localizedDescription)")
        }
    }
}
