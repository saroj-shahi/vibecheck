import SwiftUI

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
