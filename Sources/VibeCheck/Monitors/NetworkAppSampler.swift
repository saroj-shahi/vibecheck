import Foundation

struct NetworkAppRow: Sendable {
    let pid: Int32
    let name: String
    let download: Double   // bytes per second
    let upload: Double
    let responsible: Int32
}

/// Per-app network usage, summed across an app's helper processes.
struct AppNetworkUsage: Identifiable {
    let id: Int32          // responsible pid
    let name: String
    let download: Double
    let upload: Double
    var total: Double { download + upload }
}

/// Uses `nettop` in delta mode: two samples one second apart; the second block holds each process's bytes
/// over that second. Takes about a second, so it only runs while the Network panel is open.
enum NetworkAppSampler {
    static func fetch() async -> [NetworkAppRow] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: parse(run()))
            }
        }
    }

    private static func run() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "2", "-s", "1", "-d", "-x", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Lines look like `Google Chrome H.1969,3379063,1403121,`; header lines start with `,bytes_in`.
    static func parse(_ output: String, seconds: Double = 1) -> [NetworkAppRow] {
        var block = 0
        var rows: [NetworkAppRow] = []
        for line in output.split(separator: "\n") {
            if line.hasPrefix(",bytes_in") { block += 1; continue }
            guard block == 2 else { continue }
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3, let bytesIn = Double(fields[1]), let bytesOut = Double(fields[2]),
                  bytesIn > 0 || bytesOut > 0,
                  let dot = fields[0].lastIndex(of: "."), let pid = Int32(fields[0][fields[0].index(after: dot)...])
            else { continue }
            let name = String(fields[0][..<dot])
            rows.append(NetworkAppRow(pid: pid, name: name, download: bytesIn / seconds, upload: bytesOut / seconds,
                                      responsible: ProcessSampler.responsible(for: pid)))
        }
        return rows
    }

    static func groupByApp(_ rows: [NetworkAppRow], appName: (Int32) -> String?) -> [AppNetworkUsage] {
        Dictionary(grouping: rows, by: \.responsible).map { owner, members in
            AppNetworkUsage(id: owner,
                            name: appName(owner) ?? members.first { $0.pid == owner }?.name ?? members[0].name,
                            download: members.reduce(0) { $0 + $1.download },
                            upload: members.reduce(0) { $0 + $1.upload })
        }
        .sorted { $0.total > $1.total }
    }
}
