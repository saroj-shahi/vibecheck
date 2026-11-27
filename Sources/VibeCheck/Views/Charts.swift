import SwiftUI

/// Horizontal stacked bar, e.g. memory composition, with optional hover-to-inspect segments.
struct StackedBar: View {
    let segments: [(value: Double, color: Color)]
    let total: Double
    var hoveredIndex: Binding<Int?>? = nil

    var body: some View {
        let active = hoveredIndex?.wrappedValue
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, seg in
                    let width = max(0, geo.size.width * CGFloat(seg.value / max(total, 1)) - 1)
                    Rectangle()
                        .fill(seg.color)
                        .opacity(active == nil || active == index ? 1 : 0.38)
                        .frame(width: width)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            guard let binding = hoveredIndex else { return }
                            if inside {
                                binding.wrappedValue = index
                            } else if binding.wrappedValue == index {
                                binding.wrappedValue = nil
                            }
                        }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: active == nil ? 10 : 12)
        .background(.quaternary)
        .clipShape(Capsule())
        .animation(.easeOut(duration: 0.14), value: active)
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
