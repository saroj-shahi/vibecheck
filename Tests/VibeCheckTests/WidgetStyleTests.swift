import Foundation
import Testing
@testable import VibeCheck
import VibeCheckShared

@Suite struct WidgetStyleTests {
    @Test func fullColorKeepsStateColors() {
        #expect(WidgetRenderStyle.fullColor.stroke(vibe: 2, dimmed: false).usesStateColor)
        #expect(!WidgetRenderStyle.fullColor.stroke(vibe: 0, dimmed: true).usesStateColor)
        #expect(WidgetRenderStyle.fullColor.areaOpacity == 0.15)
    }

    @Test func accentedUsesNoStateColorOrFill() {
        for vibe in 0...2 {
            let tone = WidgetRenderStyle.accented.stroke(vibe: vibe, dimmed: false)
            #expect(!tone.usesStateColor && tone.opacity == 1)
        }
        #expect(WidgetRenderStyle.accented.areaOpacity == 0)
    }

    @Test func vibrantUsesOpacityHierarchy() {
        let o = (0...2).map { WidgetRenderStyle.vibrant.stroke(vibe: $0, dimmed: false).opacity }
        #expect(o[0] > o[1] && o[1] > o[2])
        #expect(WidgetRenderStyle.vibrant.stroke(vibe: 0, dimmed: false, emphasis: 0.7).opacity < o[0])
        #expect(WidgetRenderStyle.vibrant.stroke(vibe: 0, dimmed: true).opacity < o[2])
        #expect(!WidgetRenderStyle.vibrant.stroke(vibe: 1, dimmed: false).usesStateColor)
    }

    @Test func keepAwakeStateRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ka-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(!WidgetShared.readKeepAwake(from: url))
        #expect(WidgetShared.writeKeepAwake(true, to: url))
        #expect(WidgetShared.readKeepAwake(from: url))
        WidgetShared.writeKeepAwake(false, to: url)
        #expect(!WidgetShared.readKeepAwake(from: url))
    }
}
