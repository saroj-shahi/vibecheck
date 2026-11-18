import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == "VibeCheck" {
    let b = w[kCGWindowBounds as String] as! [String: Any]
    let on = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
    let layer = w[kCGWindowLayer as String] as! Int
    let a = w[kCGWindowAlpha as String] as? Double ?? 0
    print(w[kCGWindowNumber as String]!, "layer", layer, "on", on, "alpha", a, b["X"]!, b["Y"]!, b["Width"]!, b["Height"]!, w[kCGWindowName as String] ?? "")
}
