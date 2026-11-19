import ApplicationServices
// usage: axpress <pid> <label>   presses the first element whose description or title equals <label>
let pid = pid_t(CommandLine.arguments[1])!, target = CommandLine.arguments[2]
let app = AXUIElementCreateApplication(pid)
func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func find(_ e: AXUIElement, _ depth: Int) -> AXUIElement? {
    if depth > 40 { return nil }
    let label = (attr(e, kAXDescriptionAttribute) as? String) ?? (attr(e, kAXTitleAttribute) as? String)
    if label == target { return e }
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { if let f = find(c, depth + 1) { return f } }
    return nil
}
for w in (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
    if let e = find(w, 0) { print(AXUIElementPerformAction(e, kAXPressAction as CFString) == .success ? "pressed" : "press failed"); exit(0) }
}
print("not found"); exit(1)
