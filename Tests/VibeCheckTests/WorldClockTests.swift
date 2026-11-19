import Foundation
import Testing
@testable import VibeCheck

struct WorldClockTests {
    @Test func cityNameFromIdentifier() {
        #expect(WorldClock.cityName("America/New_York") == "New York")
        #expect(WorldClock.cityName("UTC") == "UTC")
    }

    @Test func relativeDescriptionUsesOffsetFromLocalTime() {
        let now = Date()
        let local = WorldClock(name: "Here", timeZoneID: TimeZone.current.identifier)
        #expect(local.relativeDescription(at: now) == "Today, same time")

        let kathmandu = WorldClock(name: "Kathmandu", timeZoneID: "Asia/Kathmandu")
        let diff = TimeZone(identifier: "Asia/Kathmandu")!.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)
        let text = kathmandu.relativeDescription(at: now)
        if diff == 0 { #expect(text.hasSuffix("same time")) }
        else { #expect(text.contains(diff > 0 ? "+" : "−")) }
    }

    @Test func clockFormatsProduceText() {
        for format in ClockFormat.allCases {
            #expect(!format.formatter(seconds: true).string(from: Date()).isEmpty)
        }
    }
}
