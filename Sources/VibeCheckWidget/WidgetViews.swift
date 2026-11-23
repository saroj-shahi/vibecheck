import SwiftUI
import VibeCheckShared
import WidgetKit

/// Same colors and fill as the app's `Vibe` (mint / yellow / red; full, two thirds, one third).
enum WidgetVibe {
    static func color(_ vibe: Int) -> Color { [Color.mint, .yellow, .red][min(max(vibe, 0), 2)] }
    static func fill(_ vibe: Int) -> Double { [1, 0.66, 0.33][min(max(vibe, 0), 2)] }
}

extension WidgetRenderingMode {
    var style: WidgetRenderStyle {
        switch self {
        case .accented: .accented
        case .vibrant: .vibrant
        default: .fullColor
        }
    }
}

extension WidgetTone {
    /// `color` is the full-color choice for this element (state color or a fixed one).
    func shapeStyle(color: Color) -> Color {
        (usesStateColor ? color : Color.primary).opacity(opacity)
    }
}

struct WidgetRing: View {
    @Environment(\.widgetRenderingMode) private var mode
    var vibe: Int
    var lineWidth: CGFloat
    var dimmed: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(mode.style.trackOpacity), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: WidgetVibe.fill(vibe))
                .stroke(mode.style.stroke(vibe: vibe, dimmed: dimmed).shapeStyle(color: WidgetVibe.color(vibe)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .padding(lineWidth / 2)
    }
}

/// Small: the ring with the vibe word inside, the reason underneath.
struct VibeRingWidgetView: View {
    var entry: SnapshotEntry

    var body: some View {
        let s = entry.snapshot
        VStack(spacing: 8) {
            WidgetRing(vibe: s.vibe, lineWidth: 9, dimmed: entry.stale)
                .overlay {
                    Text(entry.stale ? "–" : s.vibeTitle)
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                }
                .frame(maxHeight: .infinity)
            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.stale ? Text("VibeCheck isn't running") : Text(s.verdict))
    }

    private var footnote: String {
        if entry.stale { return String(localized: "Open VibeCheck to see the vibe") }
        return entry.snapshot.vibe == 0
            ? String(localized: "CPU \(Int((entry.snapshot.cpu * 100).rounded()))% · Memory \(Int((entry.snapshot.memory * 100).rounded()))%")
            : entry.snapshot.verdict
    }
}

/// Medium: vibe on the left, CPU and memory sparklines for the last hour on the right.
struct SparklineWidgetView: View {
    var entry: SnapshotEntry

    var body: some View {
        let s = entry.snapshot
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetRing(vibe: s.vibe, lineWidth: 6, dimmed: entry.stale)
                    .frame(width: 44, height: 44)
                Spacer(minLength: 0)
                Text(entry.stale ? String(localized: "Not running") : s.vibeTitle)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                Text(entry.stale ? String(localized: "Open VibeCheck") : s.verdict)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(width: 104, alignment: .leading)
            VStack(spacing: 10) {
                SparkRow(title: String(localized: "CPU"), now: s.cpu, values: s.cpuHour, color: .mint, emphasis: 1, dimmed: entry.stale)
                SparkRow(title: String(localized: "Memory"), now: s.memory, values: s.memoryHour, color: .cyan, emphasis: 0.7, dimmed: entry.stale)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct SparkRow: View {
    @Environment(\.widgetRenderingMode) private var mode
    var title: String
    var now: Double
    var values: [Double]
    var color: Color
    /// Vibrant mode tells the two lines apart by opacity instead of hue.
    var emphasis: Double
    var dimmed: Bool

    var body: some View {
        let style = mode.style
        let tone = style.stroke(vibe: 0, dimmed: dimmed, emphasis: emphasis)
        let line = dimmed ? Color.secondary : tone.shapeStyle(color: color)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(dimmed ? "–" : "\(Int((now * 100).rounded()))%")
                    .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
            }
            Sparkline(values: values)
                .stroke(line, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .background(alignment: .bottom) {
                    if style.areaOpacity > 0 {
                        Sparkline(values: values, closed: true)
                            .fill((dimmed ? Color.secondary : line).opacity(style.areaOpacity))
                    }
                }
                .widgetAccentable()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title) \(Int((now * 100).rounded())) percent"))
    }
}

/// Values 0...1, oldest first, drawn left to right across the full width.
struct Sparkline: Shape {
    var values: [Double]
    var closed = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let step = rect.width / CGFloat(values.count - 1)
        let points = values.enumerated().map { i, v in
            CGPoint(x: rect.minX + CGFloat(i) * step, y: rect.maxY - CGFloat(min(max(v, 0), 1)) * rect.height)
        }
        path.addLines(points)
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
