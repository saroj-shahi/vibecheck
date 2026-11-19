import Testing
@testable import VibeCheck

struct NetworkAppTests {
    private let sample = """
    ,bytes_in,bytes_out,
    Google Chrome H.1969,3379063,1403121,
    mDNSResponder.488,6515610,4659258,
    ,bytes_in,bytes_out,
    Google Chrome H.1969,2000,1000,
    Google Chrome H.1970,3000,0,
    some.dotted.name.42,10,20,
    idle.77,0,0,
    """

    @Test func readsOnlyTheDeltaBlock() {
        let rows = NetworkAppSampler.parse(sample)
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.download < 10_000 })   // cumulative first block ignored
        #expect(rows.contains { $0.name == "some.dotted.name" && $0.pid == 42 })
        #expect(!rows.contains { $0.pid == 77 })             // zero traffic dropped
    }

    @Test func groupsHelpersUnderTheirApp() {
        let rows = [
            NetworkAppRow(pid: 1969, name: "Google Chrome H", download: 2000, upload: 1000, responsible: 100),
            NetworkAppRow(pid: 1970, name: "Google Chrome H", download: 3000, upload: 0, responsible: 100),
            NetworkAppRow(pid: 42, name: "curl", download: 10, upload: 20, responsible: 42),
        ]
        let apps = NetworkAppSampler.groupByApp(rows) { $0 == 100 ? "Google Chrome" : nil }
        #expect(apps.first?.name == "Google Chrome")
        #expect(apps.first?.download == 5000)
        #expect(apps.last?.name == "curl")
    }
}
