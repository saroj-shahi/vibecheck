import Darwin
import Foundation

/// Writes owner-only (`0600`) files atomically via a same-directory temp file + `rename`, creating a missing
/// parent folder at `0700` (leaving an existing folder's permissions untouched).
enum AtomicPrivateFile {
    @discardableResult
    nonisolated static func write(_ data: Data, to url: URL) -> Bool {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let temp = dir.appendingPathComponent(".\(url.lastPathComponent)-\(UUID().uuidString).tmp")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { return false }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.close()
            guard rename(temp.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            return true
        } catch {
            try? fm.removeItem(at: temp)
            return false
        }
    }
}
