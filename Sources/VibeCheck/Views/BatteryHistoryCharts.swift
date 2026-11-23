import SwiftUI

/// Multi-day charge chart and max-capacity trend, from `BatteryLogStore`.
struct BatteryHistorySection: View {
    @Environment(SystemStats.self) private var stats

    var body: some View {
        let points = stats.batteryLog.points
        let now = Date().timeIntervalSince1970
        let days = min(14.0, max(1, ceil((now - (points.first?.t ?? now)) / 86_400)))
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: days == 1 ? "Charge, last \(Int(days)) day" : "Charge, last \(Int(days)) days")
            LineChart(values: points.filter { $0.t >= now - days * 86_400 }.map { ($0.t, $0.charge) },
                      from: now - days * 86_400, to: now, range: 0...1, color: .green)
                .frame(height: 56)
            let trend = BatteryLogStore.healthTrend(points)
            if trend.count >= 2 {
                let lo = max(0, (trend.map(\.health).min() ?? 0.8) - 0.02)
                let hi = min(1.2, (trend.map(\.health).max() ?? 1) + 0.02)
                SectionTitle(text: "Maximum capacity, \(Fmt.percent(trend.last?.health ?? 0)) now")
                // One point per day, so the points are always more than 3 h apart: join them all, and mark each day.
                LineChart(values: trend.map { ($0.t, $0.health) },
                          from: trend[0].t, to: max(trend[0].t + 1, now), range: lo...max(hi, lo + 0.01), color: .mint,
                          maxGap: .infinity, dots: true)
                    .frame(height: 40)
            }
        }
    }
}

private struct LineChart: View {
    var values: [(TimeInterval, Double)]
    var from: TimeInterval
    var to: TimeInterval
    var range: ClosedRange<Double>
    var color: Color
    /// Points further apart than this start a new segment (sleep, app closed). Sparse series pass `.infinity`.
    var maxGap: TimeInterval = 3 * 3600
    /// Draws a dot on every point, for series with few points.
    var dots = false

    var body: some View {
        Canvas { context, size in
            guard values.count >= 1, to > from else { return }
            func point(_ t: TimeInterval, _ v: Double) -> CGPoint {
                let x = size.width * (t - from) / (to - from)
                let y = size.height * (1 - (v - range.lowerBound) / (range.upperBound - range.lowerBound))
                return CGPoint(x: x, y: min(max(y, 2), size.height - 2))
            }
            var path = Path()
            for segment in ChartSegments.split(values.map(\.0), maxGap: maxGap) {
                path.move(to: point(values[segment.lowerBound].0, values[segment.lowerBound].1))
                for i in segment.dropFirst() { path.addLine(to: point(values[i].0, values[i].1)) }
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            if dots {
                for (t, v) in values {
                    let p = point(t, v)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(color))
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.4)))
    }
}

/// Splits chart points into runs to draw as connected lines.
enum ChartSegments {
    /// Index ranges of consecutive times no more than `maxGap` apart (times sorted ascending).
    nonisolated static func split(_ times: [TimeInterval], maxGap: TimeInterval) -> [Range<Int>] {
        guard !times.isEmpty else { return [] }
        var result: [Range<Int>] = []
        var start = 0
        for i in 1..<max(times.count, 1) where times[i] - times[i - 1] > maxGap {
            result.append(start..<i)
            start = i
        }
        result.append(start..<times.count)
        return result
    }
}
