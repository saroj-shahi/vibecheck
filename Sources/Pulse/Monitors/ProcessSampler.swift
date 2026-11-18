import Foundation

struct ProcessRow: Identifiable, Sendable {
    let id: Int32
    let name: String
    let cpu: Double     // percent of one core, as `ps` reports it
    let memory: Double  // resident bytes
}

enum ProcessSampler {
    /// Runs `ps` off the main thread and returns every process with CPU and resident memory.
    static func fetch() async -> [ProcessRow] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: run())
            }
        }
    }

    private static func run() -> [ProcessRow] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aceo", "pid=,pcpu=,rss=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let cpu = Double(parts[1]),
                  let rssKB = Double(parts[2]) else { return nil }
            return ProcessRow(id: pid, name: String(parts[3]), cpu: cpu, memory: rssKB * 1024)
        }
    }
}
