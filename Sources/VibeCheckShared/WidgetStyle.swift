import Foundation

/// How a widget is drawn on the desktop; mirrors WidgetKit's `WidgetRenderingMode` so the choices can be tested.
public enum WidgetRenderStyle: Sendable, Equatable {
    /// Normal full color.
    case fullColor
    /// Tinted desktop: the system recolors the accentable group with one tint.
    case accented
    /// Vibrant / monochrome: only opacity differences survive.
    case vibrant
}

/// A drawing decision for one element: the vibe's state color, or plain primary at an opacity.
public struct WidgetTone: Sendable, Equatable {
    public var usesStateColor: Bool
    public var opacity: Double
}

public extension WidgetRenderStyle {
    /// Ring / sparkline stroke. Full color keeps mint / yellow / red; the other modes use primary and,
    /// when vibrant, opacity for the hierarchy (vibing brightest, cooked dimmest).
    func stroke(vibe: Int, dimmed: Bool, emphasis: Double = 1) -> WidgetTone {
        switch self {
        case .fullColor: return WidgetTone(usesStateColor: !dimmed, opacity: 1)
        case .accented: return WidgetTone(usesStateColor: false, opacity: dimmed ? 0.4 : 1)
        case .vibrant:
            let byVibe = [1.0, 0.75, 0.5][min(max(vibe, 0), 2)]
            return WidgetTone(usesStateColor: false, opacity: dimmed ? 0.35 : byVibe * emphasis)
        }
    }

    /// Opacity of the area under a sparkline; none when tinting, where a fill becomes a flat blob.
    var areaOpacity: Double {
        switch self {
        case .fullColor: 0.15
        case .accented: 0
        case .vibrant: 0.1
        }
    }

    /// Opacity of the ring's background track.
    var trackOpacity: Double { self == .fullColor ? 0.15 : 0.2 }
}
