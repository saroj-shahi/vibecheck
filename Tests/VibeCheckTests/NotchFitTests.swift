import AppKit
import Testing
@testable import VibeCheck

struct NotchFitTests {
    // Built-in 1800-pt display measured on this Mac: notch from x 790 to 1010.
    let left = NSRect(x: 0, y: 1131, width: 790, height: 38)
    let right = NSRect(x: 1010, y: 1131, width: 790, height: 38)

    @Test func roomIsBetweenNotchAndRightEdge() {
        let item = NSRect(x: 712, y: 1138, width: 493, height: 22)        // crosses the notch
        let room = NotchFit.availableWidth(itemRect: item, notchRight: right, notchLeft: left)
        #expect(room.map { abs($0 - 189) < 0.5 } == true, "got \(String(describing: room))")
        let leftOfNotch = NSRect(x: 400, y: 1138, width: 300, height: 22)
        #expect(NotchFit.availableWidth(itemRect: leftOfNotch, notchRight: right, notchLeft: left) == nil)
        #expect(NotchFit.availableWidth(itemRect: item, notchRight: nil, notchLeft: nil) == nil)  // no notch
    }

    @Test func showsAsManyLeadingItemsAsFitWithAChip() {
        let widths: [CGFloat] = [54, 54, 38, 46, 38, 37, 51, 92, 46]
        // Everything fits: no limit.
        #expect(NotchFit.visibleCount(itemWidths: widths, fixed: 16, gap: 2, chipWidth: 18, available: 1000) == nil)
        // 189 pt: ring 16 + 54 + 54 + 38 + chip 18 + gaps 2×4 = 188 → three stats.
        #expect(NotchFit.visibleCount(itemWidths: widths, fixed: 16, gap: 2, chipWidth: 18, available: 189) == 3)
        // Barely any room: ring and chip only.
        #expect(NotchFit.visibleCount(itemWidths: widths, fixed: 16, gap: 2, chipWidth: 18, available: 30) == 0)
    }
}
