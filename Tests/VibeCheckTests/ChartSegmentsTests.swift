import Testing
@testable import VibeCheck

struct ChartSegmentsTests {
    @Test func dailyPointsJoinWithInfiniteGap() {
        let days: [Double] = [0, 86_400, 172_800]
        #expect(ChartSegments.split(days, maxGap: .infinity) == [0..<3])
    }

    @Test func dailyPointsAreSeparateWithThreeHourGap() {
        // The old behaviour: every point its own segment, so nothing was drawn.
        let days: [Double] = [0, 86_400, 172_800]
        #expect(ChartSegments.split(days, maxGap: 3 * 3600) == [0..<1, 1..<2, 2..<3])
    }

    @Test func sleepGapSplitsChargeLine() {
        let times: [Double] = [0, 900, 1800, 1800 + 4 * 3600, 1800 + 4 * 3600 + 900]
        #expect(ChartSegments.split(times, maxGap: 3 * 3600) == [0..<3, 3..<5])
    }

    @Test func emptyAndSingle() {
        #expect(ChartSegments.split([], maxGap: 10).isEmpty)
        #expect(ChartSegments.split([5], maxGap: 10) == [0..<1])
    }
}
