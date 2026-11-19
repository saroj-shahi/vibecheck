import ApplicationServices
import AppKit
let pid = pid_t(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
var lines = 0
func walk(_ e: AXUIElement, _ depth: Int) {
    guard depth < 30, lines < 120 else { return }
    let role = attr(e, kAXRoleAttribute) as? String ?? "?"
    let label = (attr(e, kAXDescriptionAttribute) as? String) ?? (attr(e, kAXTitleAttribute) as? String) ?? (attr(e, kAXValueAttribute) as? String) ?? ""
    if !label.isEmpty || role == "AXWindow" { print(String(repeating: " ", count: depth) + role + ": " + label.prefix(110)); lines += 1 }
    for child in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(child, depth + 1) }
}
for w in (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { walk(w, 0) }
