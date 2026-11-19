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

extension NotchFit {
    /// True when macOS has put an item behind the notch (its frame overlaps the notch gap) or off the left
    /// edge of the screen. nil areas mean the display has no notch.
    static func isHidden(itemRect: NSRect, screenFrame: NSRect, notchLeft: NSRect?, notchRight: NSRect?) -> Bool {
        guard let left = notchLeft, let right = notchRight else { return false }
        if itemRect.minX < screenFrame.minX - 1 { return true }
        let overlap = min(itemRect.maxX, right.minX) - max(itemRect.minX, left.maxX)
        return overlap > itemRect.width / 2
    }
}

/// Debounce for the notch auto-collapse: only reports once an item has stayed hidden for `hold` seconds, and
/// starts over whenever it shows up again.
struct NotchHideWatch {
    var hiddenSince: Date?

    mutating func update(hidden: Bool, now: Date, hold: TimeInterval = 8) -> Bool {
        guard hidden else { hiddenSince = nil; return false }
        let since = hiddenSince ?? now
        hiddenSince = since
        return now.timeIntervalSince(since) >= hold
    }

    /// Whether VibeCheck may collapse by itself: separate items, the fit setting on, and the owner hasn't
    /// switched separate items back on after an earlier collapse.
    static func mayCollapse(separate: Bool, autoFit: Bool, optedOut: Bool) -> Bool { separate && autoFit && !optedOut }

    static var noticeTitle: String { String(localized: "Switched to one menu bar item") }
    static var noticeBody: String { String(localized: "Your Mac's notch was hiding some items, so VibeCheck combined them. You can switch back in Settings.") }
}

private extension Bool {
    func width(_ value: CGFloat) -> CGFloat { self ? value : 0 }
}
