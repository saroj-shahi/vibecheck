import SwiftUI

/// Bell in the deck header: a dot for notifications not seen yet; click for the last 20.
struct NotificationBellButton: View {
    @State private var showing = false
    @State private var hovering = false
    private var log: NotificationLog { .shared }

    var body: some View {
        let unseen = log.unseenCount
        let help: LocalizedStringKey = unseen > 0 ? (unseen == 1 ? "\(unseen) new notification" : "\(unseen) new notifications") : "Recent notifications"
        Button { showing.toggle() } label: {
            Image(systemName: "bell")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.quaternary.opacity(hovering || showing ? 1 : 0)))
                .overlay(alignment: .topTrailing) {
                    if unseen > 0 {
                        Circle().fill(.red).frame(width: 7, height: 7).offset(x: -5, y: 5)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering } }
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            NotificationHistoryList()
                .onAppear { log.markAllSeen() }
        }
    }
}

struct NotificationHistoryList: View {
    private var log: NotificationLog { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent notifications").font(.headline)
                Spacer()
                if !log.entries.isEmpty {
                    Button("Clear") { log.clear() }.buttonStyle(.borderless).controlSize(.small)
                }
            }
            .padding(12)
            Divider()
            if log.entries.isEmpty {
                Text("Nothing yet. Alerts and keep-awake endings show up here.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(log.entries) { entry in
                            NotificationRow(entry: entry)
                            if entry.id != log.entries.last?.id { Divider().padding(.leading, 38) }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 346)
    }
}

private struct NotificationRow: View {
    let entry: LoggedNotification

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(entry.kind == .alert ? Color.orange : Color.accentColor)
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title.replacingOccurrences(of: "VibeCheck · ", with: ""))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(timeText).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Text(entry.body).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    /// "3:42 PM" today, "Yesterday 9:10 AM", otherwise "Nov 16, 9:10 AM".
    private var timeText: String {
        let time = entry.date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(entry.date) { return time }
        if Calendar.current.isDateInYesterday(entry.date) { return String(localized: "Yesterday \(time)") }
        return entry.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
