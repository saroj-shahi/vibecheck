import AppKit

/// Which background the deck draws. Liquid Glass on 26, blur before that, opaque when Reduce Transparency is on.
enum DeckBackgroundKind: Equatable {
    case liquidGlass, blur, opaque

    nonisolated static func choose(osMajor: Int, reduceTransparency: Bool) -> DeckBackgroundKind {
        if reduceTransparency { return .opaque }
        return osMajor >= 26 ? .liquidGlass : .blur
    }
}

/// First-launch check: is any VibeCheck status item actually on a menu bar, and if not, why.
enum MenuBarVisibility {
    enum Verdict: Equatable { case visible, hiddenByNotch, hiddenByMacOS }

    struct Probe {
        var hasWindow: Bool
        var isVisible: Bool
        var frame: CGRect
    }

    /// True when the item's frame sits inside some screen's menu bar strip (top 40 pt, not past the left edge).
    nonisolated static func isOnMenuBar(frame: CGRect, screenFrames: [CGRect]) -> Bool {
        screenFrames.contains { screen in
            frame.width > 0 && frame.minX >= screen.minX - 1 && frame.maxX <= screen.maxX + 1
                && frame.maxY <= screen.maxY + 1 && frame.maxY >= screen.maxY - 40
        }
    }

    /// `probes` is one entry per status item, `notchHidden` says whether NotchFit reports each as behind the notch.
    nonisolated static func verdict(probes: [(probe: Probe, notchHidden: Bool)], screenFrames: [CGRect]) -> Verdict {
        guard !probes.isEmpty else { return .visible }
        let shown = probes.contains {
            $0.probe.hasWindow && $0.probe.isVisible && !$0.notchHidden
                && isOnMenuBar(frame: $0.probe.frame, screenFrames: screenFrames)
        }
        if shown { return .visible }
        return probes.contains { $0.notchHidden } ? .hiddenByNotch : .hiddenByMacOS
    }

    static let shownKey = "vibecheckMenuBarHiddenNoticeShown"

    static var title: String { String(localized: "VibeCheck is running but you can't see it") }
    static func body(_ verdict: Verdict) -> String {
        switch verdict {
        case .hiddenByNotch: NotchHideWatch.noticeBody
        default: String(localized: "macOS is hiding it. Turn it on in System Settings → Menu Bar.")
        }
    }

    /// System Settings → Control Center, which has the Menu Bar list ("Allow in the Menu Bar"). The
    /// `.extension` pane id is not in Apple's documentation but is what System Settings itself registers.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!
}
