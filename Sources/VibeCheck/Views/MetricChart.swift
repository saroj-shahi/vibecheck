import AppKit
import SwiftUI

// MARK: - Resampling

/// Every chart range is resampled to the same number of evenly spaced buckets, so switching ranges can
/// morph one line into the next. `nil` means no data for that bucket (drawn as a gap).
enum ChartResampler {
    static let buckets = 120

    /// Live samples are right-aligned in `capacity` slots (newest at the right edge) and interpolated.
    static func live(_ values: [Double], capacity: Int, buckets: Int = buckets) -> [Double?] {
        let n = values.count
        guard n > 0, capacity > 1 else { return Array(repeating: nil, count: buckets) }
        guard n > 1 else {
            var result = [Double?](repeating: nil, count: buckets)
            result[buckets - 1] = values[0]
            return result
        }
        let firstSlot = Double(capacity - n)
        return (0..<buckets).map { b in
            let position = (Double(b) + 0.5) / Double(buckets) * Double(capacity - 1)
            guard position >= firstSlot else { return nil }
            let index = position - firstSlot
            let lo = min(Int(index), n - 1), hi = min(lo + 1, n - 1)
            let fraction = index - Double(lo)
            return values[lo] * (1 - fraction) + values[hi] * fraction
        }
    }

    /// Stored history: average the points whose bucket centre falls in each chart bucket.
    static func stored(_ points: [HistoryPoint], range: HistoryRange, end: TimeInterval,
                       buckets: Int = buckets) -> [Double?] {
        let start = end - range.span
        let width = range.span / Double(buckets)
        var sums = [Double](repeating: 0, count: buckets)
        var counts = [Int](repeating: 0, count: buckets)
        for point in points {
            let index = Int(((point.t + range.bucket / 2) - start) / width)
            guard index >= 0, index < buckets, point.v.isFinite else { continue }
            sums[index] += point.v
            counts[index] += 1
        }
        return (0..<buckets).map { counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : nil }
    }

    /// Shared scale for all series in one chart.
    static func peak(_ series: [[Double?]], maxValue: Double?, floor: Double) -> Double {
        if let maxValue { return maxValue }
        return max(series.flatMap { $0.compactMap { $0 } }.max() ?? 0, floor)
    }

    static func normalized(_ values: [Double?], peak: Double) -> [Double] {
        values.map { min(max(($0 ?? 0) / max(peak, 1e-12), 0), 1) }
    }
}

/// `[Double]` that SwiftUI can interpolate, so a whole chart line animates as one value.
struct AnimatableVector: VectorArithmetic {
    var values: [Double]

    static var zero: AnimatableVector { AnimatableVector(values: []) }

    static func + (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        combine(lhs, rhs, +)
    }

    static func - (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        combine(lhs, rhs, -)
    }

    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }

    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }

    private static func combine(_ lhs: AnimatableVector, _ rhs: AnimatableVector,
                                _ op: (Double, Double) -> Double) -> AnimatableVector {
        let count = max(lhs.values.count, rhs.values.count)
        return AnimatableVector(values: (0..<count).map { i in
            op(i < lhs.values.count ? lhs.values[i] : 0, i < rhs.values.count ? rhs.values[i] : 0)
        })
    }
}

/// One series as a line (or the area under it). Runs of missing buckets become gaps.
struct SeriesShape: Shape {
    var samples: AnimatableVector
    var valid: [Bool]
    var flipped = false
    var filled = false

    var animatableData: AnimatableVector {
        get { samples }
        set { samples = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let count = valid.count
        guard count > 0 else { return Path() }
        let values = samples.values
        let base = flipped ? rect.minY : rect.maxY
        var path = Path()
        var run: [CGPoint] = []

        func flush() {
            guard !run.isEmpty else { return }
            var points = run
            if points.count == 1 {
                points = [CGPoint(x: points[0].x - 1.5, y: points[0].y), CGPoint(x: points[0].x + 1.5, y: points[0].y)]
            }
            if filled {
                path.move(to: CGPoint(x: points[0].x, y: base))
                // Not `addLines`: it starts a new subpath, dropping the move to the baseline.
                points.forEach { path.addLine(to: $0) }
                path.addLine(to: CGPoint(x: points[points.count - 1].x, y: base))
                path.closeSubpath()
            } else {
                path.move(to: points[0])
                points.dropFirst().forEach { path.addLine(to: $0) }
            }
            run.removeAll()
        }

        for bucket in 0..<count {
            guard valid[bucket], bucket < values.count else { flush(); continue }
            let x = rect.minX + (CGFloat(bucket) + 0.5) / CGFloat(count) * rect.width
            let h = rect.height * CGFloat(values[bucket]) * 0.94
            run.append(CGPoint(x: x, y: flipped ? rect.minY + h : rect.maxY - h))
        }
        flush()
        return path
    }
}

// MARK: - Range pill

/// Live / 1H / 24H control with a pill that slides between segments.
struct RangePill: View {
    @Binding var selection: HistoryRange
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HistoryRange.allCases) { range in
                let selected = range == selection
                Text(range.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .padding(.horizontal, 9)
                    .frame(height: 20)
                    .background {
                        if selected {
                            Capsule()
                                .fill(.background)
                                .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                                .matchedGeometryEffect(id: "pill", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(Deck.reduceMotion ? .easeInOut(duration: 0.15)
                                      : .spring(response: 0.3, dampingFraction: 0.8)) { selection = range }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(range == .live ? "Live" : range == .hour ? "Last hour" : "Last 24 hours")
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(Capsule().fill(.quaternary))
    }
}

// MARK: - Metric chart

/// Chart with a range pill, morphing range changes and hover scrubbing. The range choice is shared by
/// every panel and remembered.
struct MetricChart: View {
    struct Line {
        let key: HistoryKey
        let color: Color
        var name: String? = nil
    }

    let lines: [Line]
    var maxValue: Double? = nil
    var mirrored = false
    var height: CGFloat = 70
    let format: (Double) -> String

    @AppStorage("chartRange") private var rangeRaw = HistoryRange.live.rawValue
    @Environment(SystemStats.self) private var stats
    @Environment(AppSettings.self) private var settings
    @State private var hoverBucket: Int?

    private var range: HistoryRange { HistoryRange(rawValue: rangeRaw) ?? .live }
    private var liveSpan: TimeInterval { Double(SystemStats.historyLength) * settings.refreshInterval }

    var body: some View {
        let data = resampled()
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                RangePill(selection: Binding(get: { range }, set: { rangeRaw = $0.rawValue }))
                Spacer()
                Text("Peak \(format(data.peakValue))")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    .contentTransition(.numericText())
            }
            plot(data)
                .frame(height: height)
            HStack {
                Text(range == .live ? "\(Int(liveSpan / 60)) min ago" : range == .hour ? "1 hour ago" : "24 hours ago")
                Spacer()
                Text("now")
            }
            .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: Data

    private struct Resampled {
        var raw: [[Double?]]
        var normalized: [[Double]]
        var peak: Double
        var peakValue: Double
        var peakBucket: Int?
    }

    private func resampled() -> Resampled {
        let end = Date().timeIntervalSince1970
        let raw: [[Double?]] = lines.map { line in
            range == .live
                ? ChartResampler.live(stats.live(line.key), capacity: SystemStats.historyLength)
                : ChartResampler.stored(stats.history.points(line.key, range), range: range, end: end)
        }
        let peak = ChartResampler.peak(raw, maxValue: maxValue, floor: mirrored ? 1024 : 1e-9)
        let first = raw.first ?? []
        let peakBucket = first.indices.filter { first[$0] != nil }.max { (first[$0] ?? 0) < (first[$1] ?? 0) }
        let peakValue = raw.flatMap { $0.compactMap { $0 } }.max() ?? 0
        return Resampled(raw: raw, normalized: raw.map { ChartResampler.normalized($0, peak: peak) },
                         peak: peak, peakValue: peakValue, peakBucket: peakBucket)
    }

    // MARK: Drawing

    private func plot(_ data: Resampled) -> some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                grid(size)
                if mirrored, lines.count == 2 {
                    VStack(spacing: 0) {
                        series(0, data, flipped: false).frame(height: size.height / 2)
                        series(1, data, flipped: true).frame(height: size.height / 2)
                    }
                    Rectangle().fill(.secondary.opacity(0.35)).frame(height: 0.5)
                        .offset(y: size.height / 2)
                } else {
                    ForEach(lines.indices, id: \.self) { series($0, data, flipped: false) }
                }
                if let bucket = hoverBucket {
                    scrubOverlay(bucket, data, size)
                }
            }
            .animation(Deck.animation, value: rangeRaw)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let bucket = min(max(Int(location.x / max(size.width, 1) * CGFloat(ChartResampler.buckets)), 0),
                                     ChartResampler.buckets - 1)
                    guard bucket != hoverBucket else { return }
                    withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.9)) { hoverBucket = bucket }
                    if bucket == data.peakBucket {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                case .ended:
                    withAnimation(.easeOut(duration: 0.15)) { hoverBucket = nil }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.45)))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("\(range == .live ? "Live" : range.label) chart, peak \(format(data.peakValue))")
    }

    private func series(_ index: Int, _ data: Resampled, flipped: Bool) -> some View {
        let samples = AnimatableVector(values: data.normalized[index])
        let valid = data.raw[index].map { $0 != nil }
        let color = lines[index].color
        return ZStack {
            SeriesShape(samples: samples, valid: valid, flipped: flipped, filled: true)
                .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)],
                                     startPoint: flipped ? .bottom : .top, endPoint: flipped ? .top : .bottom))
            SeriesShape(samples: samples, valid: valid, flipped: flipped)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    private func grid(_ size: CGSize) -> some View {
        Canvas { context, size in
            var path = Path()
            for i in 1..<4 {
                let y = size.height * CGFloat(i) / 4
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)
        }
    }

    // MARK: Scrubbing

    private func scrubOverlay(_ bucket: Int, _ data: Resampled, _ size: CGSize) -> some View {
        let x = (CGFloat(bucket) + 0.5) / CGFloat(ChartResampler.buckets) * size.width
        let atPeak = bucket == data.peakBucket
        let accent = lines.first?.color ?? .accentColor
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(atPeak ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary.opacity(0.6)))
                .frame(width: 1, height: size.height)
                .offset(x: x - 0.5)
            ForEach(lines.indices, id: \.self) { index in
                if data.raw[index][bucket] != nil {
                    let value = data.normalized[index][bucket]
                    let flipped = mirrored && index == 1
                    let half = mirrored ? size.height / 2 : size.height
                    let h = half * CGFloat(value) * 0.94
                    let y = flipped ? half + h : half - h
                    Circle()
                        .fill(lines[index].color)
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                        .frame(width: 7, height: 7)
                        .offset(x: x - 3.5, y: y - 3.5)
                }
            }
            Text(bubbleText(bucket, data))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText())
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .fixedSize()
                .frame(width: size.width, alignment: .center)
                .offset(x: min(max(x - size.width / 2, -size.width / 2 + 70), size.width / 2 - 70), y: 4)
        }
        .allowsHitTesting(false)
    }

    private func bubbleText(_ bucket: Int, _ data: Resampled) -> String {
        let values = lines.indices.compactMap { index -> String? in
            guard let value = data.raw[index][bucket] else { return nil }
            let prefix = lines[index].name.map { "\($0) " } ?? (mirrored ? (index == 0 ? "↑ " : "↓ ") : "")
            return prefix + format(value)
        }
        let when: String
        let fraction = (Double(bucket) + 0.5) / Double(ChartResampler.buckets)
        if range == .live {
            let secondsAgo = Int(((1 - fraction) * liveSpan).rounded())
            when = secondsAgo < 3 ? "now" : secondsAgo < 60 ? "\(secondsAgo)s ago" : "\(secondsAgo / 60)m \(secondsAgo % 60)s ago"
        } else {
            let date = Date(timeIntervalSinceNow: -(1 - fraction) * range.span)
            when = date.formatted(date: .omitted, time: .shortened)
        }
        return (values.isEmpty ? ["No data"] : values).joined(separator: " · ") + " · " + when
    }
}
