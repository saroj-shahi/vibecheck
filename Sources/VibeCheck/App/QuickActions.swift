import AppKit
import CoreAudio
import Foundation
import IOBluetooth
import Observation

/// Outcome of a quick action; `failure` carries a short message for the deck.
enum QuickResult: Equatable, Sendable {
    case ok
    case failure(String)
}

/// Pure helpers, kept separate so they can be tested without touching the system.
enum QuickActionsText {
    static let automationDenied = String(localized: "Allow VibeCheck to control Finder in System Settings → Privacy & Security → Automation.")
    static let genericFailure = String(localized: "That didn't work. Try again.")

    /// The AppleScript error number macOS reports when Automation access is denied.
    static let deniedCode = -1743

    /// Maps an AppleScript error number to the message shown in the deck.
    static func failureMessage(code: Int) -> String {
        code == deniedCode ? automationDenied : genericFailure
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

/// The quick toggles on the deck home.
enum QuickToggle: Sendable { case mic, bluetooth }

/// What tapping the Bluetooth toggle does. Pure, for tests.
enum BluetoothTap: Equatable, Sendable {
    case setPower(Bool)
    /// First use: show the Bluetooth permission prompt.
    case askPermission
    /// Access was turned down: point to System Settings.
    case denied
    /// The private calls are missing on this macOS.
    case unavailable

    static func decide(available: Bool, access: BluetoothSnooze.Access, poweredOn: Bool?) -> BluetoothTap {
        guard available else { return .unavailable }
        switch access {
        case .notAsked: return .askPermission
        case .denied: return .denied
        case .allowed:
            guard let poweredOn else { return .unavailable }
            return .setPower(!poweredOn)
        }
    }

    static let askMessage = String(localized: "Allow Bluetooth for VibeCheck, then tap again.")
    static let deniedMessage = String(localized: "Allow VibeCheck to use Bluetooth in System Settings → Privacy & Security → Bluetooth.")
    static let unavailableMessage = String(localized: "Bluetooth can't be switched from here on this Mac.")

    /// VoiceOver label for the toggle.
    static func spoken(poweredOn: Bool?) -> String {
        switch poweredOn {
        case true?: String(localized: "Bluetooth, on")
        case false?: String(localized: "Bluetooth, off")
        case nil: String(localized: "Bluetooth")
        }
    }
}

/// Microphone mute, Bluetooth power and Empty Trash, run on request only.
@MainActor
@Observable
final class QuickActions {
    static let shared = QuickActions()

    private(set) var isMicMuted = false
    /// Bluetooth controller power; nil when unknown (no access yet, or the private call is missing).
    private(set) var bluetoothOn: Bool?
    /// Items in ~/.Trash; nil when it can't be read (no access).
    private(set) var trashCount: Int? = 0
    private(set) var failure: String?
    /// Which toggle's action failed last, and a counter that changes on every failure (even a repeat),
    /// so a chip can shake each time.
    private(set) var failedToggle: QuickToggle?
    private(set) var failureTick = 0
    private var failureTask: Task<Void, Never>?
    private var bluetoothReadBack: Task<Void, Never>?
    /// Input volume to restore when the device has no mute switch and was silenced via its volume.
    private var savedVolume: Float32?

    // MARK: Refresh

    func refresh() {
        isMicMuted = Self.readMicMuted()
        bluetoothOn = BluetoothSnooze.shared.isPoweredOn
        Task {
            let count = await Task.detached { Self.countTrash() }.value
            trashCount = count
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
            let result = await Self.runAppleScript(#"tell application "Finder" to empty trash"#)
            switch result {
            case .ok: trashCount = 0
            case .failure(let message): show(message)
            }
            refresh()
        }
    }

    // MARK: AppleScript

    /// Runs on a background thread; NSAppleScript is created there and never shared.
    nonisolated private static func runAppleScript(_ source: String) async -> QuickResult {
        await Task.detached {
            guard let script = NSAppleScript(source: source) else { return QuickResult.failure(QuickActionsText.genericFailure) }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            guard let error else { return .ok }
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            return .failure(QuickActionsText.failureMessage(code: code))
        }.value
    }

    // MARK: Bluetooth

    /// Set by a first "off" tap while a Bluetooth keyboard or mouse is connected; a second tap before it passes confirms.
    @ObservationIgnored private var bluetoothOffArmedUntil: Date?

    /// A connected peripheral-class device (keyboard, mouse, trackpad: Bluetooth major class 0x05).
    private static func bluetoothInputConnected() -> Bool {
        (IOBluetoothDevice.pairedDevices() ?? []).contains { item in
            guard let device = item as? IOBluetoothDevice, device.isConnected() else { return false }
            return device.deviceClassMajor == 0x05
        }
    }

    func toggleBluetooth() {
        let snooze = BluetoothSnooze.shared
        switch BluetoothTap.decide(available: snooze.isAvailable, access: snooze.access, poweredOn: snooze.isPoweredOn) {
        case .setPower(let on):
            // Turning Bluetooth off can strand a Mac whose only keyboard or mouse is Bluetooth, so with one
            // connected the first tap only warns and a second tap within 5 s does it.
            if !on, Self.bluetoothInputConnected(), (bluetoothOffArmedUntil ?? .distantPast) < Date() {
                bluetoothOffArmedUntil = Date().addingTimeInterval(5)
                show(String(localized: "Your Bluetooth keyboard or mouse will disconnect. Tap again to turn Bluetooth off."), duration: 5)
                return
            }
            bluetoothOffArmedUntil = nil
            guard snooze.setPowered(on) else { show(QuickActionsText.genericFailure, toggle: .bluetooth); return }
            bluetoothOn = on
            // The controller takes a moment to settle; read back what it really did. Only the latest tap's
            // read-back counts, so a quick on-off-on can't end showing an older state.
            bluetoothReadBack?.cancel()
            bluetoothReadBack = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                bluetoothOn = BluetoothSnooze.shared.isPoweredOn
            }
        case .askPermission:
            snooze.requestAccess()
            show(BluetoothTap.askMessage, toggle: .bluetooth)
            // Once the user answers the system prompt, show the real state without waiting for a reopen.
            // Bounded: checks once a second for 30 s at most.
            bluetoothReadBack?.cancel()
            bluetoothReadBack = Task {
                for _ in 0..<30 {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    if BluetoothSnooze.shared.access != .notAsked {
                        bluetoothOn = BluetoothSnooze.shared.isPoweredOn
                        return
                    }
                }
            }
        case .denied:
            show(BluetoothTap.deniedMessage, toggle: .bluetooth)
        case .unavailable:
            show(BluetoothTap.unavailableMessage, toggle: .bluetooth)
        }
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

    private func show(_ message: String, toggle: QuickToggle? = nil, duration: Double = 3) {
        if let toggle { failedToggle = toggle; failureTick &+= 1 }
        failure = message
        failureTask?.cancel()
        failureTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            if !Task.isCancelled { failure = nil }
        }
    }
}
