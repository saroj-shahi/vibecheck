import Foundation

/// One TCP listener, with IPv4/IPv6 duplicates of the same pid + port already merged.
struct ListeningPort: Identifiable, Equatable, Sendable {
    let pid: Int32
    let name: String
    let port: Int
    let address: String   // "127.0.0.1", "::1", "*" or a LAN address
    let user: String

    var id: String { "\(pid):\(port)" }

    /// Loopback listeners can't be reached from other machines; `*` and LAN addresses can.
    var isLocalOnly: Bool { ListeningPort.isLoopback(address) }

    static func isLoopback(_ address: String) -> Bool {
        address == "::1" || address == "localhost" || address.hasPrefix("127.")
    }
}

/// Listening TCP ports via `lsof`. Only the current user's processes are visible without root.
/// Runs only while the Network panel is open (see `SystemStats.networkAppDemand`).
enum PortSampler {
    static func fetch() async -> [ListeningPort] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: parse(run()))
            }
        }
    }

    private static func run() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-FpcnL"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// `lsof -F` output: one field per line, the first character names it. `p` starts a process
    /// (followed by `c` command and `L` login), each `n` is an address like `*:3000`, `127.0.0.1:5432`
    /// or `[::1]:8080`. Unknown or malformed lines are skipped. Sorted by port, then pid.
    static func parse(_ output: String) -> [ListeningPort] {
        var pid: Int32?
        var name = ""
        var user = ""
        var merged: [String: ListeningPort] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value)
                name = ""
                user = ""
            case "c": name = value
            case "L": user = value
            case "n":
                guard let pid, pid > 0, !name.isEmpty,
                      let colon = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: colon)...]), (1...65535).contains(port)
                else { continue }
                var address = String(value[..<colon])
                if address.hasPrefix("["), address.hasSuffix("]") { address = String(address.dropFirst().dropLast()) }
                guard !address.isEmpty else { continue }
                let entry = ListeningPort(pid: pid, name: name, port: port, address: address, user: user)
                if let existing = merged[entry.id] {
                    // IPv4 + IPv6 twins: keep the more exposed one so "local only" is never overstated.
                    if existing.isLocalOnly, !entry.isLocalOnly { merged[entry.id] = entry }
                } else {
                    merged[entry.id] = entry
                }
            default: continue
            }
        }
        return merged.values.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }
}
