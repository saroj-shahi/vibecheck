import AppKit
import Observation

/// How many stats the combined item currently shows. `nil` means all of them.
@Observable
@MainActor
final class CombinedFit {
    var visibleCount: Int?
}

enum NotchFit {
    /// Largest number of leading items that fit in `available` points, or nil when everything fits.
    /// `fixed` covers the ring and outer padding; a "+N" chip is reserved whenever something is hidden.
    static func visibleCount(itemWidths: [CGFloat], fixed: CGFloat, gap: CGFloat,
                             chipWidth: CGFloat, available: CGFloat) -> Int? {
        func width(_ count: Int, chip: Bool) -> CGFloat {
            let parts = itemWidths.prefix(count).reduce(0, +)
            let pieces = count + (chip ? 1 : 0)
            return fixed + parts + chip.width(chipWidth) + gap * CGFloat(pieces)
        }
        if width(itemWidths.count, chip: false) <= available { return nil }
        var count = itemWidths.count - 1
        while count > 0, width(count, chip: true) > available { count -= 1 }
        return count
    }

    /// Applies the user's "at most N beside the notch" cap (0 = no cap) to the fitted count.
    /// Returns nil when every stat is shown.
    static func capped(fitted: Int?, total: Int, cap: Int) -> Int? {
        var count = fitted ?? total
        if cap > 0 { count = min(count, cap) }
        return count >= total ? nil : count
    }

    /// Room for the combined item between the notch's right edge and the item's own right edge, which
    /// stays put as the item changes width. nil when the item's display has no notch or the item sits
    /// entirely left of it.
    static func availableWidth(itemRect: NSRect, notchRight: NSRect?, notchLeft: NSRect?) -> CGFloat? {
        guard let right = notchRight, let left = notchLeft else { return nil }
        guard itemRect.maxX > left.maxX else { return nil }       // entirely left of the notch
        return max(0, itemRect.maxX - right.minX - 6)
    }
}

private extension Bool {
    func width(_ value: CGFloat) -> CGFloat { self ? value : 0 }
}
