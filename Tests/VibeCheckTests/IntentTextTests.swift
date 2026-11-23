import Testing
@testable import VibeCheck

@Suite struct IntentTextTests {
    private let apps = [
        CulpritSummary(name: "Slack", cpu: 6, memory: 900_000_000, processCount: 4),
        CulpritSummary(name: "Chrome", cpu: 42.4, memory: 3_000_000_000, processCount: 20),
        CulpritSummary(name: "Xcode", cpu: 18, memory: 2_000_000_000, processCount: 3),
    ]

    @Test func defaultMetricFollowsCulprit() {
        #expect(CulpritMetric.defaultMetric(culprit: .memory) == .memory)
        #expect(CulpritMetric.defaultMetric(culprit: .cpu) == .cpu)
        #expect(CulpritMetric.defaultMetric(culprit: .network) == .cpu)
        #expect(CulpritMetric.defaultMetric(culprit: nil) == .cpu)
    }

    @Test func culpritsRankAndLimit() {
        #expect(CulpritText.top(apps, metric: .cpu, count: 2).map(\.name) == ["Chrome", "Xcode"])
        #expect(CulpritText.top(apps, metric: .memory, count: 1).map(\.name) == ["Chrome"])
        #expect(CulpritText.top(apps, metric: .cpu, count: 99).count == 3)
    }

    @Test func culpritDialog() {
        let top = CulpritText.top(apps, metric: .cpu, count: 3)
        #expect(CulpritText.dialog(top, metric: .cpu) == "Chrome 42% CPU, Xcode 18%, Slack 6%.")
        #expect(CulpritText.dialog([], metric: .cpu) == "Nothing is busy right now.")
        #expect(CulpritText.dialog(Array(top.prefix(1)), metric: .memory).hasSuffix("memory."))
    }

    @Test func stopConfirmationAndResult() {
        let web = DevServerTarget(name: "web", ports: [3000], identities: [])
        let api = DevServerTarget(name: "api", ports: [8080, 8081], identities: [])
        #expect(DevServerText.confirmation([web, api]) == "Stop 2 dev servers: web (3000), api (8080, 8081)?")
        #expect(DevServerText.confirmation([web]) == "Stop 1 dev server: web (3000)?")
        #expect(DevServerText.result(stopped: ["web", "api"], refused: []) == "Stopped web, api.")
        #expect(DevServerText.result(stopped: ["web"], refused: [("api", "Not permitted")])
                == "Stopped web. Couldn't stop api: Not permitted.")
        #expect(DevServerText.result(stopped: [], refused: []) == "No dev servers are running.")
    }

    @Test func targetsUseSampledIdentity() {
        let d = ListenerDetails(executable: "/usr/local/bin/node", workingDirectory: "/Users/x/web", uid: 501,
                                startedSeconds: 10, startedMicros: 10_000_123, footprint: nil,
                                projectFolder: "/Users/x/web", projectName: "web")
        let port = ListeningPort(pid: 42, name: "node", port: 3000, address: "127.0.0.1", user: "x", details: d)
        let t = DevServerText.targets(from: [port], home: "/Users/x", currentUID: 501)
        #expect(t == [DevServerTarget(name: "web", ports: [3000], identities: [.init(pid: 42, started: 10_000_123)])])
    }
}
