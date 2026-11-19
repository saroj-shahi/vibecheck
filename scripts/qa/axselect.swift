import ApplicationServices
// usage: axselect <pid> <text>   selects the AXRow that contains static text <text>
let pid = pid_t(CommandLine.arguments[1])!, target = CommandLine.arguments[2]
let app = AXUIElementCreateApplication(pid)
func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func contains(_ e: AXUIElement, _ depth: Int) -> Bool {
    if depth > 8 { return false }
    if (attr(e, kAXValueAttribute) as? String) == target || (attr(e, kAXTitleAttribute) as? String) == target
        || (attr(e, kAXDescriptionAttribute) as? String) == target { return true }
    return ((attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []).contains { contains($0, depth + 1) }
}
func find(_ e: AXUIElement, _ depth: Int) -> AXUIElement? {
    if depth > 30 { return nil }
    if (attr(e, kAXRoleAttribute) as? String) == "AXRow", contains(e, 0) { return e }
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { if let f = find(c, depth + 1) { return f } }
    return nil
}
for w in (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
    if let row = find(w, 0) {
        let r = AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue)
        print(r == .success ? "selected" : "select failed \(r.rawValue)"); exit(0)
    }
}
print("not found"); exit(1)
