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
                LineChart(values: trend.map { ($0.t, $0.health) },
                          from: trend[0].t, to: max(trend[0].t + 1, now), range: lo...max(hi, lo + 0.01), color: .mint)
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

    var body: some View {
        Canvas { context, size in
            guard values.count >= 1, to > from else { return }
            var path = Path()
            var last: TimeInterval?
            for (t, v) in values {
                let x = size.width * (t - from) / (to - from)
                let y = size.height * (1 - (v - range.lowerBound) / (range.upperBound - range.lowerBound))
                let p = CGPoint(x: x, y: min(max(y, 0), size.height))
                // A long gap (sleep, app closed) stays a gap.
                if let l = last, t - l <= 3 * 3600 { path.addLine(to: p) } else { path.move(to: p) }
                last = t
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.4)))
    }
}
