import AppKit
import CoreAudio
import Foundation
import Observation

/// Outcome of a quick action; `failure` carries a short message for the deck.
enum QuickResult: Equatable, Sendable {
    case ok
    case failure(String)
}

/// Pure helpers, kept separate so they can be tested without touching the system.
enum QuickActionsText {
    static let automationDenied = String(localized: "Allow VibeCheck to control System Events in System Settings → Privacy & Security → Automation.")
    static let automationDeniedFinder = String(localized: "Allow VibeCheck to control Finder in System Settings → Privacy & Security → Automation.")
    static let genericFailure = String(localized: "That didn't work. Try again.")

    /// The AppleScript error number macOS reports when Automation access is denied.
    static let deniedCode = -1743

    /// Maps an AppleScript error number to the message shown in the deck.
    static func failureMessage(code: Int, target: String = "System Events") -> String {
        guard code == deniedCode else { return genericFailure }
        return target == "Finder" ? automationDeniedFinder : automationDenied
    }

    /// Chip label: "Trash" when empty or unreadable, otherwise "Trash 12".
    static func trashLabel(count: Int?) -> String {
        guard let count, count > 0 else { return "Trash" }
        return String(localized: "Trash \(count)")
    }

    /// Inline question shown before emptying.
    static func confirmPrompt(count: Int?) -> String {
        guard let count else { return String(localized: "Empty Trash?") }
        return count == 1 ? String(localized: "Empty \(count) item?") : String(localized: "Empty \(count) items?")
    }

    static func trashSpoken(count: Int?) -> String {
        guard let count else { return String(localized: "Empty Trash") }
        if count == 0 { return String(localized: "Empty Trash, nothing to empty") }
        return count == 1 ? String(localized: "Empty Trash, \(count) item") : String(localized: "Empty Trash, \(count) items")
    }
}

/// The two quick toggles on the deck home.
enum QuickToggle: Sendable { case dark, mic }

/// Dark mode, microphone mute and Empty Trash, run on request only.
@MainActor
@Observable
final class QuickActions {
    static let shared = QuickActions()

    private(set) var isDark = false
    private(set) var isMicMuted = false
    /// Items in ~/.Trash; nil when it can't be read (no access).
    private(set) var trashCount: Int? = 0
    private(set) var failure: String?
    /// Which toggle's action failed last, and a counter that changes on every failure (even a repeat),
    /// so a chip can shake each time.
    private(set) var failedToggle: QuickToggle?
    private(set) var failureTick = 0
    private var failureTask: Task<Void, Never>?
    /// Input volume to restore when the device has no mute switch and was silenced via its volume.
    private var savedVolume: Float32?

    // MARK: Refresh

    func refresh() {
        isDark = Self.systemIsDark()
        isMicMuted = Self.readMicMuted()
        Task {
            let count = await Task.detached { Self.countTrash() }.value
            trashCount = count
        }
    }

    // MARK: Dark mode

    nonisolated static func systemIsDark() -> Bool {
        UserDefaults(suiteName: "Apple Global Domain")?.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    func toggleDarkMode() {
        let script = #"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#
        Task {
            let result = await Self.runAppleScript(script, target: "System Events")
            switch result {
            case .ok: isDark.toggle()
            case .failure(let message): show(message, toggle: .dark)
            }
        }
    }

    // MARK: Empty Trash

    nonisolated static func countTrash(fileManager: FileManager = .default) -> Int? {
        let url = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard let items = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                               options: []) else { return nil }
        return items.filter { $0.lastPathComponent != ".DS_Store" }.count
    }

    func emptyTrash() {
        Task {
            let result = await Self.runAppleScript(#"tell application "Finder" to empty trash"#, target: "Finder")
            switch result {
            case .ok: trashCount = 0
            case .failure(let message): show(message)
            }
            refresh()
        }
    }

    // MARK: AppleScript

    /// Runs on a background thread; NSAppleScript is created there and never shared.
    nonisolated private static func runAppleScript(_ source: String, target: String) async -> QuickResult {
        await Task.detached {
            guard let script = NSAppleScript(source: source) else { return QuickResult.failure(QuickActionsText.genericFailure) }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            guard let error else { return .ok }
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            return .failure(QuickActionsText.failureMessage(code: code, target: target))
        }.value
    }

    // MARK: Microphone

    func toggleMic() {
        let muted = Self.readMicMuted()
        if let message = setMicMuted(!muted) { show(message, toggle: .mic) }
        isMicMuted = Self.readMicMuted()
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func inputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeInput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func isSettable(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = inputAddress(selector)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func readUInt32(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = inputAddress(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func readVolume(_ device: AudioDeviceID) -> Float32? {
        var address = inputAddress(kAudioDevicePropertyVolumeScalar)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func writeUInt32(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ value: UInt32) -> Bool {
        var address = inputAddress(selector)
        var v = value
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }

    private static func writeVolume(_ device: AudioDeviceID, _ value: Float32) -> Bool {
        var address = inputAddress(kAudioDevicePropertyVolumeScalar)
        var v = value
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }

    /// True when the default input is muted (mute switch on, or volume at 0 for devices without one).
    static func readMicMuted() -> Bool {
        guard let device = defaultInputDevice() else { return false }
        if let mute = readUInt32(device, kAudioDevicePropertyMute) { return mute != 0 }
        if let volume = readVolume(device) { return volume == 0 }
        return false
    }

    /// Returns a failure message, or nil on success.
    private func setMicMuted(_ muted: Bool) -> String? {
        guard let device = Self.defaultInputDevice() else { return String(localized: "No microphone found.") }
        if Self.isSettable(device, kAudioDevicePropertyMute) {
            return Self.writeUInt32(device, kAudioDevicePropertyMute, muted ? 1 : 0) ? nil : String(localized: "Couldn't change the microphone.")
        }
        guard Self.isSettable(device, kAudioDevicePropertyVolumeScalar), let current = Self.readVolume(device) else {
            return String(localized: "This microphone can't be muted.")
        }
        if muted {
            if current > 0 { savedVolume = current }
            return Self.writeVolume(device, 0) ? nil : String(localized: "Couldn't change the microphone.")
        }
        let restore = savedVolume ?? 0.75
        savedVolume = nil
        return Self.writeVolume(device, restore) ? nil : String(localized: "Couldn't change the microphone.")
    }

    // MARK: Failure message

    private func show(_ message: String, toggle: QuickToggle? = nil) {
        if let toggle { failedToggle = toggle; failureTick &+= 1 }
        failure = message
        failureTask?.cancel()
        failureTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { failure = nil }
        }
    }
}
