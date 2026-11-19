import Foundation
import Testing
@testable import VibeCheck

struct NetworkExtrasTests {
    @Test func publicIPParsing() {
        #expect(PublicIPFetcher.parse("203.0.113.7\n") == "203.0.113.7")
        #expect(PublicIPFetcher.parse("2001:db8::1") == "2001:db8::1")
        #expect(PublicIPFetcher.parse("<html>login</html>") == nil)
        #expect(PublicIPFetcher.parse("") == nil)
    }

    @Test func publicIPSchedule() {
        let now = Date()
        #expect(PublicIPFetcher.isDue(lastFetch: nil, now: now, networkChanged: false))
        #expect(!PublicIPFetcher.isDue(lastFetch: now.addingTimeInterval(-60), now: now, networkChanged: false))
        #expect(PublicIPFetcher.isDue(lastFetch: now.addingTimeInterval(-60), now: now, networkChanged: true))
        #expect(PublicIPFetcher.isDue(lastFetch: now.addingTimeInterval(-601), now: now, networkChanged: false))
    }

    @Test func trafficHistoryAccumulatesAndExpires() {
        var history = AppTrafficHistory()
        let t0 = Date(timeIntervalSince1970: 6000)
        let a = AppNetworkUsage(id: 1, name: "A", download: 100, upload: 10)
        let b = AppNetworkUsage(id: 2, name: "B", download: 1000, upload: 0)
        history.record([a, b], seconds: 2, now: t0)
        history.record([a], seconds: 1, now: t0.addingTimeInterval(61))
        let top = history.top(limit: 5, now: t0.addingTimeInterval(61))
        #expect(top.map(\.name) == ["B", "A"])
        #expect(top[1].download == 300 && top[1].upload == 30)
        // Two hours later everything has aged out.
        #expect(history.top(limit: 5, now: t0.addingTimeInterval(7200)).isEmpty)
    }

    @Test func wifiNames() {
        #expect(WiFiInfo.bandName(.band5GHz) == "5 GHz")
        #expect(WiFiInfo.bandName(nil) == nil)
        #expect(WiFiInfo.phyName(.mode11ax) == "Wi-Fi 6 (802.11ax)")
    }
}
