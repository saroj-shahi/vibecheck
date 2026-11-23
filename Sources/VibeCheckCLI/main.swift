import Foundation
import VibeCheckShared

// The `vibecheck` command line tool: one file read, no processes, no AppKit.

func err(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
func out(_ text: String) { print(text) }

let help = """
usage: vibecheck <command>

  status [--json]                          how the Mac is doing, in a sentence (or the raw JSON)
  mood                                     vibing, mid or cooked; exit code 0, 1 or 2
  culprits [--top N] [--by memory|cpu] [--json]
                                           the apps using the most memory (or CPU, when the deck is open)
  --help, --version

Exit code 3 means VibeCheck isn't running (no status yet). Reads \(StatusSnapshot.defaultURL().path).
"""

func appVersion() -> String {
    // Installed at VibeCheck.app/Contents/Helpers/vibecheck (maybe through a symlink).
    let exe = URL(fileURLWithPath: CommandLine.arguments[0].hasPrefix("/") ? CommandLine.arguments[0] : FileManager.default.currentDirectoryPath + "/" + CommandLine.arguments[0])
        .resolvingSymlinksInPath()
    let plist = exe.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
    if let data = try? Data(contentsOf: plist),
       let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
       let v = dict["CFBundleShortVersionString"] as? String { return v }
    return "dev"
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { out(help); exit(0) }
args.removeFirst()

switch command {
case "--help", "-h", "help": out(help); exit(0)
case "--version", "-v": out("vibecheck \(appVersion())"); exit(0)
case "status", "mood", "culprits": break
default: err("vibecheck: unknown command '\(command)'. Try --help."); exit(64)
}

let json = args.contains("--json")
var top = 5, by = "memory"
var i = 0
while i < args.count {
    switch args[i] {
    case "--json": break
    case "--top":
        i += 1
        guard i < args.count, let n = Int(args[i]), n > 0 else { err("vibecheck: --top needs a number."); exit(64) }
        top = n
    case "--by":
        i += 1
        guard i < args.count, ["memory", "cpu"].contains(args[i]) else { err("vibecheck: --by is memory or cpu."); exit(64) }
        by = args[i]
    default: err("vibecheck: unknown option '\(args[i])'."); exit(64)
    }
    i += 1
}

let snapshot: StatusSnapshot
switch StatusSnapshot.load(try? Data(contentsOf: StatusSnapshot.defaultURL())) {
case .missing:
    err("VibeCheck isn't running (no status yet).")
    exit(3)
case .unreadable:
    err("Couldn't read VibeCheck's status file.")
    exit(1)
case .snapshot(let loaded):
    snapshot = loaded
}
let now = Date()
let stale = snapshot.isStale(now: now) { pid in kill(pid, 0) == 0 || errno == EPERM }

func fail(_ error: Error) -> Never {
    err("Couldn't write the result: \(error.localizedDescription)")
    exit(1)
}

switch command {
case "mood":
    if stale { err(snapshot.notRunningMessage()); exit(3) }
    out(snapshot.vibe)
    exit(snapshot.moodExitCode)
case "status":
    do {
        if json { out(String(decoding: try snapshot.cliJSON(stale: stale), as: UTF8.self)) } else { out(snapshot.humanStatus(stale: stale)) }
    } catch { fail(error) }
default:
    if stale { err(snapshot.notRunningMessage()); exit(3) }
    if by == "cpu", snapshot.freshTopCPU(now: now) == nil { err("CPU details need the VibeCheck deck open; showing memory.") }
    let result = snapshot.culpritLines(by: by, top: top, now: now)
    if json {
        do {
            let enc = StatusSnapshot.makeEncoder()
            if result.usedCPU { out(String(decoding: try enc.encode(Array((snapshot.freshTopCPU(now: now) ?? []).prefix(top))), as: UTF8.self)) }
            else { out(String(decoding: try enc.encode(Array(snapshot.topMemory.prefix(top))), as: UTF8.self)) }
        } catch { fail(error) }
    } else if result.lines.isEmpty {
        out("Nothing to report yet.")
    } else {
        result.lines.forEach(out)
    }
}
