import Testing
@testable import VibeCheck

struct PortSamplerTests {
    private let sample = """
    p700
    cControlCenter
    Lleapfrog
    f9
    n*:7000
    f10
    n*:7000
    p4321
    cnode
    Lleapfrog
    f21
    n127.0.0.1:3000
    f22
    n[::1]:3000
    f23
    n127.0.0.1:9229
    p555
    cpostgres
    Lleapfrog
    f5
    n[::1]:5432
    f6
    n127.0.0.1:5432
    p900
    ccupsd
    Lroot
    f7
    n[fe80::1]:631
    """

    @Test func mergesIPv4AndIPv6TwinsAndSortsByPort() {
        let rows = PortSampler.parse(sample)
        #expect(rows.map(\.port) == [631, 3000, 5432, 7000, 9229])
        #expect(rows.filter { $0.port == 3000 }.count == 1)
        #expect(rows.filter { $0.port == 7000 }.count == 1)
    }

    @Test func multiplePortsPerPid() {
        let rows = PortSampler.parse(sample).filter { $0.pid == 4321 }
        #expect(rows.map(\.port) == [3000, 9229])
        #expect(rows.allSatisfy { $0.name == "node" && $0.user == "leapfrog" })
    }

    @Test func addressKinds() {
        let rows = PortSampler.parse(sample)
        #expect(rows.first { $0.port == 7000 }?.address == "*")
        #expect(rows.first { $0.port == 7000 }?.isLocalOnly == false)
        #expect(rows.first { $0.port == 9229 }?.address == "127.0.0.1")
        #expect(rows.first { $0.port == 9229 }?.isLocalOnly == true)
        #expect(rows.first { $0.port == 5432 }?.isLocalOnly == true)
        #expect(rows.first { $0.port == 631 }?.address == "fe80::1")
        #expect(rows.first { $0.port == 631 }?.isLocalOnly == false)
    }

    @Test func mergeKeepsTheMoreExposedAddress() {
        let out = "p1\ncweb\nLme\nf1\nn127.0.0.1:8080\nf2\nn*:8080\n"
        let rows = PortSampler.parse(out)
        #expect(rows.count == 1)
        #expect(rows[0].address == "*")
    }

    @Test func ipv6LoopbackOnlyIsLocal() {
        let rows = PortSampler.parse("p1\ncweb\nLme\nf1\nn[::1]:8080\n")
        #expect(rows.count == 1 && rows[0].address == "::1" && rows[0].isLocalOnly)
    }

    @Test func samePortDifferentPidsStaySeparate() {
        let rows = PortSampler.parse("p1\ncone\nLme\nn*:80\np2\nctwo\nLme\nn127.0.0.1:80\n")
        #expect(rows.count == 2)
    }

    @Test func garbageIsSkipped() {
        let out = """
        lsof: WARNING: something
        nnoprocess:99
        pabc
        cbad
        n*:1234
        p10
        cgood
        Lme
        nnonsense
        n*:notaport
        n*:70000
        n:80
        n*:8080
        zunknown

        """
        let rows = PortSampler.parse(out)
        #expect(rows.count == 1)
        #expect(rows[0].name == "good" && rows[0].port == 8080)
        #expect(PortSampler.parse("").isEmpty)
    }
}
