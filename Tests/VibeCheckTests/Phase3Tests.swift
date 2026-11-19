import AppKit
import SwiftUI
import Testing
@testable import VibeCheck

struct ModuleOrderTests {
    @Test func storedOrderIsKeptAndCompleted() {
        let order = AppSettings.completeOrder([.network, .cpu, .network, .clock])
        #expect(Array(order.prefix(3)) == [.network, .cpu, .clock])     // duplicates dropped, order kept
        #expect(Set(order) == Set(Module.allCases))                       // new modules appended
        #expect(order.count == Module.allCases.count)
        #expect(AppSettings.completeOrder([]) == Module.allCases)
    }
}

struct AlertScrubTests {
    @Test func dragMapsToValueChanges() {
        #expect(AlertScrub.value(start: 80, dx: 40, fine: false, range: 1...100) == 90)    // 4 pt per unit
        #expect(AlertScrub.value(start: 80, dx: 40, fine: true, range: 1...100) == 83)     // 12 pt per unit
        #expect(AlertScrub.value(start: 80, dx: -400, fine: false, range: 1...100) == 1)   // clamped
        #expect(AlertScrub.value(start: 95, dx: 400, fine: false, range: 30...110) == 110)
    }
}

@MainActor
struct FlowLayoutTests {
    @Test func wrapsWordsWhenTooNarrow() {
        func height(width: CGFloat) -> CGFloat {
            let view = FlowLayout(spacing: 5, lineSpacing: 6) {
                ForEach(0..<6, id: \.self) { _ in Color.red.frame(width: 60, height: 20) }
            }
            .frame(width: width)
            return NSHostingView(rootView: view).fittingSize.height
        }
        let wide = height(width: 500), narrow = height(width: 200)
        #expect(abs(wide - 20) < 0.5, "one line, got \(wide)")
        #expect(abs(narrow - 46) < 0.5, "two lines of three, got \(narrow)")
    }
}
