import SwiftUI

/// A thin bar of vibing / mid / cooked over the last 24 hours, with the weekly sentence under it.
/// Reads `SystemStats.vibeReplay`; ready to drop into the deck home.
struct VibeStripView: View {
    @Environment(SystemStats.self) private var stats

    var body: some View {
        let episodes = stats.vibeReplay.all
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let segments = VibeReplayStore.segments(episodes)
                ZStack(alignment: .leading) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        Rectangle().fill(seg.vibe.color.opacity(seg.vibe == .vibing ? 0.55 : 1))
                            .frame(width: max(1, geo.size.width * (seg.end - seg.start)))
                            .offset(x: geo.size.width * seg.start)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
            HStack {
                Text(VibeReplayStore.weeklySummary(episodes))
                Spacer()
                Text("Last 24 h")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vibe over the last 24 hours. \(VibeReplayStore.weeklySummary(episodes))")
    }
}
