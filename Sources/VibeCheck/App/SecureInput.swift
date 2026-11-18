import AppKit
import Carbon.HIToolbox
import IOKit

/// Reports whether some app holds Secure Event Input (password field, Terminal's "Secure Keyboard Entry"),
/// which makes macOS silently drop global shortcuts, and which app it is.
///
/// The owning pid is an undocumented IORegistry value (`kCGSSessionSecureInputPID`, inside the root
/// entry's `IOConsoleUsers` array). It is looked up defensively: if it is missing or the format changes,
/// we still report that secure input is on, just without an app name. Only read on demand, never on a timer.
struct SecureInputStatus: Equatable, Sendable {
    /// Name of the app holding secure input, when it could be determined.
    var appName: String?

    /// Plain-language warning for Settings.
    var message: String {
        // macOS records the app that was frontmost when secure input started, which isn't always the one
        // holding it (seen 2026-11-18: a command-line tool's secure input was reported as Chrome's).
        let generic = "Look for an open password field, or Secure Keyboard Entry in a terminal app."
        if let appName {
            return "Shortcuts are paused while secure keyboard entry is on. macOS points to \(appName). " + generic
        }
        return "Shortcuts are paused while secure keyboard entry is on. " + generic
    }
}

@MainActor
enum SecureInput {
    /// nil when secure input is off.
    static func current() -> SecureInputStatus? {
        guard IsSecureEventInputEnabled() else { return nil }
        guard let pid = owningPID() else { return SecureInputStatus(appName: nil) }
        return SecureInputStatus(appName: appName(forPID: pid))
    }

    static func owningPID() -> pid_t? {
        if let pid = pidFromIORegistry() { return pid }
        return pidFromIORegCommand()
    }

    static func appName(forPID pid: pid_t) -> String? {
        let running = NSRunningApplication(processIdentifier: pid)
        return displayName(localizedName: running?.localizedName, processName: processName(forPID: pid))
    }

    // MARK: - Reading (private API, defensive)

    private static func pidFromIORegistry() -> pid_t? {
        let root = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return nil }
        return pid(inConsoleUsers: users)
    }

    private static func pidFromIORegCommand() -> pid_t? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        task.arguments = ["-l", "-w", "0", "-d", "1"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return pid(fromIORegText: text)
    }

    private static func processName(forPID pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    // MARK: - Pure parsing and mapping

    /// Finds `kCGSSessionSecureInputPID` in the value of `IOConsoleUsers` (an array of dictionaries).
    /// Accepts numbers or numeric strings; ignores zero, negative and malformed values.
    nonisolated static func pid(inConsoleUsers value: Any?) -> pid_t? {
        guard let users = value as? [Any] else { return nil }
        for user in users {
            guard let dict = user as? [String: Any], let raw = dict["kCGSSessionSecureInputPID"] else { continue }
            let number: Int?
            if let n = raw as? NSNumber { number = n.intValue }
            else if let s = raw as? String { number = Int(s.trimmingCharacters(in: .whitespaces)) }
            else { number = nil }
            if let number, number > 0, number <= Int(Int32.max) { return pid_t(number) }
        }
        return nil
    }

    /// Fallback: pulls the pid out of `ioreg -l -w 0` text such as `"kCGSSessionSecureInputPID"=412`.
    nonisolated static func pid(fromIORegText text: String) -> pid_t? {
        let key = "\"kCGSSessionSecureInputPID\""
        var search = text[...]
        while let range = search.range(of: key) {
            var rest = search[range.upperBound...].drop { $0 == " " || $0 == "=" }
            let digits = rest.prefix { $0.isNumber }
            rest = rest.dropFirst(digits.count)
            if let n = Int(digits), n > 0, n <= Int(Int32.max) { return pid_t(n) }
            search = rest
        }
        return nil
    }

    /// Prefers the app's localized name, then the process name; nil when both are empty.
    nonisolated static func displayName(localizedName: String?, processName: String?) -> String? {
        for candidate in [localizedName, processName] {
            if let name = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        }
        return nil
    }
}
