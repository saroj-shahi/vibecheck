import CoreGraphics
import Foundation
// usage: key <keycode> [cmd|ctrl-alt-cmd]
let code = CGKeyCode(Int(CommandLine.arguments[1])!)
var flags: CGEventFlags = []
if CommandLine.arguments.count > 2 {
    for m in CommandLine.arguments[2].split(separator: "-") {
        switch m { case "cmd": flags.insert(.maskCommand); case "ctrl": flags.insert(.maskControl); case "alt": flags.insert(.maskAlternate); case "shift": flags.insert(.maskShift); default: break }
    }
}
let src = CGEventSource(stateID: .hidSystemState)
for down in [true, false] {
    let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!
    e.flags = flags
    e.post(tap: .cghidEventTap)
    usleep(50_000)
}
