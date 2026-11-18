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
    func y(_ v: Double) -> CGFloat {
        let h = size.height * CGFloat(min(v / peak, 1))
        return flipped ? h : size.height - h
    }
    let base: CGFloat = flipped ? 0 : size.height

    var line = Path()
    for (i, v) in s.values.enumerated() {
        let p = CGPoint(x: start + step * CGFloat(i), y: y(v))
        i == 0 ? line.move(to: p) : line.addLine(to: p)
    }
    var area = line
    area.addLine(to: CGPoint(x: size.width, y: base))
    area.addLine(to: CGPoint(x: start, y: base))
    area.closeSubpath()

    let gradient = Gradient(colors: [s.color.opacity(0.45), s.color.opacity(0.08)])
    let from = CGPoint(x: 0, y: flipped ? size.height : 0)
    let to = CGPoint(x: 0, y: flipped ? 0 : size.height)
    context.fill(area, with: .linearGradient(gradient, startPoint: from, endPoint: to))
    context.stroke(line, with: .color(s.color), lineWidth: 1.2)
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
