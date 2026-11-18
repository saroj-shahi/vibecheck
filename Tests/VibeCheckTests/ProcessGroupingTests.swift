import Testing
@testable import VibeCheck

struct ProcessGroupingTests {
    @Test func helpersRollUpIntoTheirApp() {
        let rows = [
            ProcessRow(id: 100, name: "Google Chrome", cpu: 5, memory: 500, responsible: 100),
            ProcessRow(id: 101, name: "Google Chrome Helper", cpu: 10, memory: 300, responsible: 100),
            ProcessRow(id: 102, name: "Google Chrome Helper (Renderer)", cpu: 20, memory: 200, responsible: 100),
            ProcessRow(id: 200, name: "kernel_task", cpu: 3, memory: 50, responsible: 200),
        ]
        let apps = SystemStats.groupByApp(rows) { $0 == 100 ? "Chrome" : nil }
            .sorted { $0.cpu > $1.cpu }
        #expect(apps.count == 2)
        #expect(apps[0].name == "Chrome")
        #expect(apps[0].cpu == 35)
        #expect(apps[0].memory == 1000)
        #expect(apps[0].processCount == 3)
        #expect(apps[1].name == "kernel_task") // falls back to the process's own name
    }
}
