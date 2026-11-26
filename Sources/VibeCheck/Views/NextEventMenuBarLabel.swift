import SwiftUI

/// What the optional standalone Next Event menu bar item draws.
struct NextEventDisplay: Equatable, Sendable {
    let event: CalendarEvent
    let countdown: String
    let isHappening: Bool

    /// Whether left-clicking the whole item immediately joins the video call (when "Click to join" is enabled).
    nonisolated func canQuickJoin(at now: Date) -> Bool {
        guard event.videoCall != nil else { return false }
        return event.isHappening(at: now) || event.startsSoon(at: now, withinMinutes: 5)
    }

    /// Whether the inline "Join" pill should appear in the menu bar for this event (active or starting within 15 min).
    nonisolated func showsJoinPill(at now: Date, enabled: Bool) -> Bool {
        guard enabled, event.videoCall != nil else { return false }
        return event.isHappening(at: now) || event.startsSoon(at: now, withinMinutes: 15)
    }
}

/// Pure selection & formatting logic for the standalone Next Event menu bar item.
enum NextEventLogic {
    nonisolated static func display(events: [CalendarEvent],
                                    now: Date,
                                    hiddenCalendarIDs: Set<String> = [],
                                    dismissedEventIDs: Set<String> = [],
                                    onlyVideoCalls: Bool = false,
                                    showDuringEntireEvent: Bool = true,
                                    lookaheadMinutes: Int = 240) -> NextEventDisplay? {
        let eligible = events.filter { !dismissedEventIDs.contains($0.id) }
        guard let next = CalendarLogic.nextEvent(in: eligible,
                                                 now: now,
                                                 hiddenCalendarIDs: hiddenCalendarIDs,
                                                 onlyVideoCalls: onlyVideoCalls,
                                                 showDuringEntireEvent: showDuringEntireEvent,
                                                 lookaheadMinutes: lookaheadMinutes) else { return nil }
        return NextEventDisplay(
            event: next,
            countdown: CalendarLogic.compactCountdown(for: next, now: now),
            isHappening: next.isHappening(at: now)
        )
    }

    /// Truncated title so the menu bar item stays predictable and never jitters neighboring items.
    nonisolated static func shortTitle(_ title: String, maxChars: Int) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars, maxChars >= 4 else { return trimmed }
        return String(trimmed.prefix(maxChars - 1)) + "…"
    }
}

/// Optional standalone menu bar item showing the next upcoming or active calendar event + countdown,
/// with an inline clickable "Join" pill when a video call is starting soon or in progress.
struct NextEventMenuBarLabel: View {
    /// Width reserved on the trailing side for the inline Join pill hit zone.
    static let joinPillWidth: CGFloat = 46

    @Environment(AppSettings.self) private var settings
    private var store: CalendarStore { .shared }
    private var ticker: ClockTicker { .shared }
    let dismissedEventIDs: Set<String>

    var body: some View {
        let now = ticker.now
        let clock = settings.clock
        let item = NextEventLogic.display(
            events: store.events,
            now: now,
            hiddenCalendarIDs: clock.hiddenCalendarIDs,
            dismissedEventIDs: dismissedEventIDs,
            onlyVideoCalls: clock.nextEventOnlyVideoCalls,
            showDuringEntireEvent: clock.nextEventShowDuringEntireEvent,
            lookaheadMinutes: clock.nextEventLookaheadHours * 60
        )

        Group {
            if let item {
                let calColor = Color(red: item.event.red, green: item.event.green, blue: item.event.blue)
                let showJoin = item.showsJoinPill(at: now, enabled: clock.nextEventShowJoinButton)
                let maxWidth = CGFloat(clock.nextEventMaxWidth) + (showJoin ? Self.joinPillWidth + 6 : 0)
                HStack(spacing: 4) {
                    Circle()
                        .fill(settings.menuBar.colorful ? calColor : .primary)
                        .frame(width: 6, height: 6)
                    if item.event.videoCall != nil && !showJoin {
                        Image(systemName: "video.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(item.isHappening && settings.menuBar.colorful ? Color.accentColor : .primary)
                    }
                    if clock.nextEventShowTitle {
                        Text(item.event.title)
                            .font(.system(size: 12, weight: item.isHappening ? .semibold : .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(item.countdown)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(item.isHappening ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .fixedSize()
                    if showJoin {
                        HStack(spacing: 2.5) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 8.5, weight: .semibold))
                            Text("Join")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(width: Self.joinPillWidth, height: 16)
                        .background(Capsule().fill(settings.menuBar.colorful ? Color.accentColor : Color.primary.opacity(0.75)))
                        .fixedSize()
                    }
                }
                .padding(.horizontal, item.isHappening ? 6 : settings.menuBar.spacing.padding)
                .frame(height: 18)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .background {
                    if item.isHappening {
                        Capsule().fill(Color.accentColor.opacity(settings.menuBar.colorful ? 0.22 : 0.14))
                    }
                }
                .frame(height: 22)
                .accessibilityLabel(showJoin
                                    ? String(localized: "\(item.event.title), \(item.countdown), join video call available")
                                    : "\(item.event.title), \(item.countdown)")
            } else {
                EmptyView()
            }
        }
    }
}
