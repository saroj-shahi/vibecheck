import AppKit
import SwiftUI
import Testing
@testable import VibeCheck

struct ChartResamplerTests {
    @Test func liveDataIsRightAlignedWithABlankLeftEdge() {
        // 10 samples in 90 slots: only the right ~10% of buckets have data.
        let values = (0..<10).map(Double.init)
        let buckets = ChartResampler.live(values, capacity: 90)
        #expect(buckets.count == ChartResampler.buckets)
        #expect(buckets.first! == nil)
        #expect(buckets.last! != nil)
        let validCount = buckets.compactMap { $0 }.count
        #expect(validCount > 8 && validCount < 20)
        // Interpolated values stay within the sample range and increase left to right.
        let valid = buckets.compactMap { $0 }
        #expect(valid.allSatisfy { $0 >= 0 && $0 <= 9 })
        #expect(zip(valid, valid.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func fullLiveHistoryFillsEveryBucket() {
        let buckets = ChartResampler.live(Array(repeating: 0.5, count: 90), capacity: 90)
        #expect(buckets.allSatisfy { $0 == 0.5 })
    }

    @Test func storedHistoryKeepsGaps() {
        let end: TimeInterval = 1_000_000
        // Data only in the first and last 10 minutes of the hour.
        let early = stride(from: end - 3600, to: end - 3000, by: 6).map { HistoryPoint(t: $0, v: 1) }
        let late = stride(from: end - 600, to: end - 6, by: 6).map { HistoryPoint(t: $0, v: 3) }
        let buckets = ChartResampler.stored(early + late, range: .hour, end: end)
        #expect(buckets[0] == 1)
        #expect(buckets[60] == nil)                 // the middle of the hour is a gap
        #expect(buckets[ChartResampler.buckets - 2] == 3)
    }

    @Test func peakIsSharedAndRespectsFloorsAndFixedScales() {
        let a: [Double?] = [1, nil, 4], b: [Double?] = [2, 8, nil]
        #expect(ChartResampler.peak([a, b], maxValue: nil, floor: 0) == 8)
        #expect(ChartResampler.peak([a, b], maxValue: 1, floor: 0) == 1)
        #expect(ChartResampler.peak([[nil]], maxValue: nil, floor: 1024) == 1024)
        #expect(ChartResampler.normalized([4, nil, 16], peak: 8) == [0.5, 0, 1])
    }

    @Test func animatableVectorInterpolates() {
        var from = AnimatableVector(values: [0, 10])
        let to = AnimatableVector(values: [10, 20, 30])
        var delta = to - from
        delta.scale(by: 0.5)
        from += delta
        #expect(from.values == [5, 15, 15])
        #expect(AnimatableVector(values: [3, 4]).magnitudeSquared == 25)
    }
}

@MainActor
struct DetailLayoutTests {
    @Test func detailsCollapseToShortenAPanel() {
        let stats = SystemStats()
        let key = "details.cpu"
        let original = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(original, forKey: key) }
        func height() -> CGFloat {
            NSHostingView(rootView: ModulePanel(module: .cpu)
                .environment(stats).environment(AppSettings.shared)).fittingSize.height
        }
        UserDefaults.standard.set(false, forKey: key)
        let collapsed = height()
        UserDefaults.standard.set(true, forKey: key)
        let expanded = height()
        print("cpu detail heights → collapsed \(Int(collapsed)), expanded \(Int(expanded))")
        #expect(expanded > collapsed + 60)
    }
}
