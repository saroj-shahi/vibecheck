import SwiftUI
import VibeCheckShared
import WidgetKit

@main
struct VibeCheckWidgets: WidgetBundle {
    var body: some Widget {
        VibeRingWidget()
        SparklineWidget()
        if #available(macOS 26, *) {
            KeepAwakeControl()
        }
    }
}

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
    /// No snapshot yet, or the app hasn't written one in a while.
    var stale: Bool
}

/// Reads the app's snapshot. The app asks WidgetKit to reload when the vibe changes; otherwise the
/// widgets check back every 15 minutes, which is as often as WidgetKit's budget comfortably allows.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder, stale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        var entries = [entry(at: now)]
        // Dim on time if the app stops writing (quit, sleep): a second entry when the snapshot goes stale.
        if let snapshot = WidgetShared.read(), !snapshot.isStale(at: now) {
            let staleAt = snapshot.date.addingTimeInterval(WidgetSnapshot.staleAfter + 1)
            entries.append(SnapshotEntry(date: staleAt, snapshot: snapshot, stale: true))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }

    private func entry(at now: Date) -> SnapshotEntry {
        guard let snapshot = WidgetShared.read() else {
            return SnapshotEntry(date: now, snapshot: .placeholder, stale: true)
        }
        return SnapshotEntry(date: now, snapshot: snapshot, stale: snapshot.isStale(at: now))
    }
}

struct VibeRingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.ringKind, provider: SnapshotProvider()) { entry in
            VibeRingWidgetView(entry: entry)
        }
        .configurationDisplayName("Vibe")
        .description("Your Mac's vibe, with the reason when it isn't vibing.")
        .supportedFamilies([.systemSmall])
    }
}

struct SparklineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.sparklineKind, provider: SnapshotProvider()) { entry in
            SparklineWidgetView(entry: entry)
        }
        .configurationDisplayName("CPU and Memory")
        .description("The last hour of CPU and memory, with the vibe.")
        .supportedFamilies([.systemMedium])
    }
}
