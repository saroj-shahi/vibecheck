import SwiftUI

struct ChartSeries {
    let values: [Double]
    let color: Color
}

/// Right-aligned area chart: newest sample at the right edge, like a scrolling strip chart.
struct AreaChart: View {
    let series: [ChartSeries]
    var maxValue: Double? = nil
    var capacity: Int = SystemStats.historyLength

    var body: some View {
        Canvas { context, size in
            drawGrid(context, size)
            let peak = maxValue ?? max(series.flatMap(\.values).max() ?? 0, 1)
            for s in series {
                drawArea(s, peak: peak, in: context, size: size, flipped: false)
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Upload drawn upward from the midline, download downward, sharing one scale.
struct MirrorChart: View {
    let up: ChartSeries
    let down: ChartSeries
    var capacity: Int = SystemStats.historyLength

    var body: some View {
        Canvas { context, size in
            drawGrid(context, size)
            let peak = max((up.values + down.values).max() ?? 0, 1024)
            let half = CGSize(width: size.width, height: size.height / 2)
            drawArea(up, peak: peak, in: context, size: half, flipped: false)
            var lower = context
            lower.translateBy(x: 0, y: size.height / 2)
            drawArea(down, peak: peak, in: lower, size: half, flipped: true)
            var mid = Path()
            mid.move(to: CGPoint(x: 0, y: size.height / 2))
            mid.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(mid, with: .color(.secondary.opacity(0.4)), lineWidth: 0.5)
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private func drawGrid(_ context: GraphicsContext, _ size: CGSize) {
    var grid = Path()
    for i in 1..<4 {
        let y = size.height * CGFloat(i) / 4
        grid.move(to: CGPoint(x: 0, y: y))
        grid.addLine(to: CGPoint(x: size.width, y: y))
    }
    context.stroke(grid, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)
}

private func drawArea(_ s: ChartSeries, peak: Double, in context: GraphicsContext,
                      size: CGSize, flipped: Bool, capacity: Int = SystemStats.historyLength) {
    guard s.values.count > 1 else { return }
    let step = size.width / CGFloat(max(capacity - 1, 1))
    let start = size.width - step * CGFloat(s.values.count - 1)
    let points = s.values.enumerated().map { i, v in
        CGPoint(x: start + step * CGFloat(i), y: chartY(v, peak: peak, height: size.height, flipped: flipped))
    }
    fillLine(points, color: s.color, in: context, size: size, flipped: flipped)
}

private func chartY(_ v: Double, peak: Double, height: CGFloat, flipped: Bool) -> CGFloat {
    let h = height * CGFloat(min(max(v, 0) / max(peak, 1e-9), 1))
    return flipped ? h : height - h
}

/// Draws a line plus a gradient fill down to the baseline (top edge when flipped).
private func fillLine(_ points: [CGPoint], color: Color, in context: GraphicsContext, size: CGSize, flipped: Bool) {
    guard let first = points.first, let last = points.last else { return }
    let base: CGFloat = flipped ? 0 : size.height
    var line = Path()
    line.addLines(points)
    var area = line
    area.addLine(to: CGPoint(x: last.x, y: base))
    area.addLine(to: CGPoint(x: first.x, y: base))
    area.closeSubpath()

    let gradient = Gradient(colors: [color.opacity(0.45), color.opacity(0.08)])
    let from = CGPoint(x: 0, y: flipped ? size.height : 0)
    let to = CGPoint(x: 0, y: flipped ? 0 : size.height)
    context.fill(area, with: .linearGradient(gradient, startPoint: from, endPoint: to))
    context.stroke(line, with: .color(color), lineWidth: 1.2)
}

/// Time-positioned chart for stored history. Breaks the line where data is missing (sleep, app closed).
struct TimeSeriesChart: View {
    let series: [(points: [HistoryPoint], color: Color)]
    let range: HistoryRange
    let end: Date
    var maxValue: Double? = nil
    var mirrored = false   // first series up, second down

    var body: some View {
        Canvas { context, size in
            drawGrid(context, size)
            let all = series.flatMap { $0.points.map(\.v) }
            var peak = maxValue ?? max(all.max() ?? 0, 1e-9)
            if mirrored { peak = max(peak, 1024) }
            let startTime = end.timeIntervalSince1970 - range.span
            let half = CGSize(width: size.width, height: mirrored ? size.height / 2 : size.height)

            for (index, s) in series.enumerated() {
                let flipped = mirrored && index == 1
                var ctx = context
                if flipped { ctx.translateBy(x: 0, y: size.height / 2) }
                for segment in segments(s.points) {
                    var pts = segment.map { p in
                        CGPoint(x: CGFloat((p.t + range.bucket / 2 - startTime) / range.span) * size.width,
                                y: chartY(p.v, peak: peak, height: half.height, flipped: flipped))
                    }
                    if pts.count == 1 { pts = [pts[0].applying(.init(translationX: -1.5, y: 0)),
                                               pts[0].applying(.init(translationX: 1.5, y: 0))] }
                    fillLine(pts, color: s.color, in: ctx, size: half, flipped: flipped)
                }
            }
            if mirrored {
                var mid = Path()
                mid.move(to: CGPoint(x: 0, y: size.height / 2))
                mid.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(mid, with: .color(.secondary.opacity(0.4)), lineWidth: 0.5)
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func segments(_ points: [HistoryPoint]) -> [[HistoryPoint]] {
        var result: [[HistoryPoint]] = []
        var current: [HistoryPoint] = []
        for p in points {
            if let prev = current.last, p.t - prev.t > range.bucket * 2.5 {
                result.append(current)
                current = []
            }
            current.append(p)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

/// Chart with a Live / 1H / 24H switch shared by every panel (the choice is remembered).
struct MetricChart: View {
    struct Line {
        let key: HistoryKey
        let color: Color
    }

    let lines: [Line]
    var maxValue: Double? = nil
    var mirrored = false
    var height: CGFloat = 70
    let format: (Double) -> String

    @AppStorage("chartRange") private var rangeRaw = HistoryRange.live.rawValue
    @Environment(SystemStats.self) private var stats

    var body: some View {
        let range = HistoryRange(rawValue: rangeRaw) ?? .live
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Picker("Range", selection: $rangeRaw) {
                    ForEach(HistoryRange.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 120)
                Spacer()
                Text("Peak \(format(peak(range)))")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            chart(range).frame(height: height)
            if range != .live {
                HStack {
                    Text(range == .hour ? "1 hour ago" : "24 hours ago")
                    Spacer()
                    Text("now")
                }
                .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func chart(_ range: HistoryRange) -> some View {
        if range == .live {
            let series = lines.map { ChartSeries(values: stats.live($0.key), color: $0.color) }
            if mirrored, series.count == 2 {
                MirrorChart(up: series[0], down: series[1])
            } else {
                AreaChart(series: series, maxValue: maxValue)
            }
        } else {
            TimeSeriesChart(series: lines.map { (stats.history.points($0.key, range), $0.color) },
                            range: range, end: Date(), maxValue: maxValue, mirrored: mirrored)
        }
    }

    private func peak(_ range: HistoryRange) -> Double {
        let values = range == .live
            ? lines.flatMap { stats.live($0.key) }
            : lines.flatMap { stats.history.points($0.key, range).map(\.v) }
        return values.max() ?? 0
    }
}

/// Horizontal stacked bar, e.g. memory composition.
struct StackedBar: View {
    let segments: [(value: Double, color: Color)]
    let total: Double

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    Rectangle().fill(seg.color)
                        .frame(width: max(0, geo.size.width * CGFloat(seg.value / max(total, 1)) - 1))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .background(.quaternary)
        .clipShape(Capsule())
    }
}

struct CapacityBar: View {
    let fraction: Double
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
                }
        }
        .frame(height: 6)
    }
}
