import AudioToolbox
import CoreAudio
import Foundation
import Observation

/// Slider levels (volume, brightness): clamping, percent text and symbols. Pure, for tests.
enum LevelMath {
    /// Clamps to 0…1; NaN becomes 0.
    nonisolated static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return value == .infinity ? 1 : 0 }
        return min(max(value, 0), 1)
    }

    /// Whole percent, 0…100.
    nonisolated static func percent(_ value: Double) -> Int {
        Int((clamp(value) * 100).rounded())
    }

    /// "42%". At most four characters, so the label's fixed-width slot never grows.
    nonisolated static func percentText(_ value: Double) -> String {
        "\(percent(value))%"
    }

    /// Speaker symbol for a volume level.
    nonisolated static func speakerSymbol(volume: Double, muted: Bool) -> String {
        let level = clamp(volume)
        if muted || level == 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    /// VoiceOver value for the volume slider.
    nonisolated static func volumeSpoken(volume: Double, muted: Bool) -> String {
        let text = percentText(volume)
        return muted ? String(localized: "Muted, \(text)") : text
    }
}

/// What the volume slider talks to; the real one is CoreAudio, tests inject a fake.
@MainActor
protocol VolumeBackend: AnyObject {
    /// Default output volume 0…1, or nil when there's no output or its volume can't be set
    /// (some HDMI and digital outputs).
    func readVolume() -> Double?
    /// Mute state, or nil when the device has no settable mute switch.
    func readMuted() -> Bool?
    @discardableResult func writeVolume(_ value: Double) -> Bool
    @discardableResult func writeMuted(_ muted: Bool) -> Bool
    /// Calls `onChange` (on the main thread) whenever the default output, its volume or its mute changes.
    func startObserving(_ onChange: @escaping @MainActor () -> Void)
    func stopObserving()
}

/// Output volume and mute of the default output device, for the deck's volume slider.
@MainActor
@Observable
final class SystemVolume {
    static let shared = SystemVolume(backend: CoreAudioVolume())

    /// False hides the slider: no output device, or its volume can't be set.
    private(set) var isAvailable = false
    private(set) var volume: Double = 0
    private(set) var isMuted = false
    /// The device has a mute switch we can flip (otherwise the speaker icon is decoration only).
    private(set) var canMute = false
    /// True while the slider is being dragged: device updates are ignored so the knob doesn't jump.
    var isEditing = false

    @ObservationIgnored private let backend: VolumeBackend
    @ObservationIgnored private var observing = false

    init(backend: VolumeBackend) {
        self.backend = backend
    }

    func refresh() {
        guard let level = backend.readVolume() else {
            isAvailable = false
            canMute = false
            isMuted = false
            return
        }
        isAvailable = true
        if !isEditing { volume = LevelMath.clamp(level) }
        let muted = backend.readMuted()
        canMute = muted != nil
        isMuted = muted ?? false
    }

    /// Sets the volume (clamped). Moving the slider up unmutes, like the volume keys do.
    func setVolume(_ value: Double) {
        let level = LevelMath.clamp(value)
        // A drag reports every pixel; only a change of a whole percent is worth a CoreAudio write.
        guard (level * 100).rounded() != (volume * 100).rounded() || level == 0 || level == 1 else { return }
        volume = level
        if isMuted, canMute, level > 0, backend.writeMuted(false) { isMuted = false }
        backend.writeVolume(level)
    }

    func toggleMute() {
        guard canMute else { return }
        if backend.writeMuted(!isMuted) { isMuted.toggle() }
    }

    /// Starts listening for changes (idempotent). No polling: CoreAudio calls back.
    func start() {
        refresh()
        guard !observing else { return }
        observing = true
        backend.startObserving { [weak self] in
            // Our own writes during a drag echo back here; the knob already shows them.
            guard let self, !self.isEditing else { return }
            self.refresh()
        }
    }

    func stop() {
        // Closing the deck mid-drag never reports the end of editing; don't stay stuck ignoring updates.
        isEditing = false
        guard observing else { return }
        observing = false
        backend.stopObserving()
    }
}

/// The default output device through CoreAudio. `VirtualMainVolume` is the same control as the volume
/// keys: it covers devices whose volume lives on separate channels.
@MainActor
final class CoreAudioVolume: VolumeBackend {
    private var device: AudioDeviceID?
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var onChange: (@MainActor () -> Void)?

    private static let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private static func outputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static var volumeSelector: AudioObjectPropertySelector { kAudioHardwareServiceDeviceProperty_VirtualMainVolume }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = defaultOutputAddress
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func isSettable(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = outputAddress(selector)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    func readVolume() -> Double? {
        guard let device = Self.defaultOutputDevice(), Self.isSettable(device, Self.volumeSelector) else { return nil }
        var address = Self.outputAddress(Self.volumeSelector)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    func readMuted() -> Bool? {
        guard let device = Self.defaultOutputDevice(), Self.isSettable(device, kAudioDevicePropertyMute) else { return nil }
        var address = Self.outputAddress(kAudioDevicePropertyMute)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    func writeVolume(_ value: Double) -> Bool {
        guard let device = Self.defaultOutputDevice() else { return false }
        var address = Self.outputAddress(Self.volumeSelector)
        var v = Float32(LevelMath.clamp(value))
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }

    func writeMuted(_ muted: Bool) -> Bool {
        guard let device = Self.defaultOutputDevice() else { return false }
        var address = Self.outputAddress(kAudioDevicePropertyMute)
        var v: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }

    // MARK: Listeners

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { CoreAudioVolume.deviceChanged() }
        }
        var address = Self.defaultOutputAddress
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
            systemListener = block
        }
        Self.current = self
        watchDevice()
    }

    func stopObserving() {
        unwatchDevice()
        if let block = systemListener {
            var address = Self.defaultOutputAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
            systemListener = nil
        }
        onChange = nil
        if Self.current === self { Self.current = nil }
    }

    /// The observing instance, so the listener blocks don't capture a main-actor object.
    private static weak var current: CoreAudioVolume?

    private static func deviceChanged() {
        guard let current else { return }
        current.watchDevice()
        current.onChange?()
    }

    private static func levelChanged() {
        current?.onChange?()
    }

    /// Moves the volume and mute listeners to the current default output.
    private func watchDevice() {
        let now = Self.defaultOutputDevice()
        guard now != device || deviceListener == nil else { return }
        unwatchDevice()
        guard let now else { return }
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { CoreAudioVolume.levelChanged() }
        }
        for selector in [Self.volumeSelector, kAudioDevicePropertyMute] {
            var address = Self.outputAddress(selector)
            guard AudioObjectHasProperty(now, &address) else { continue }
            AudioObjectAddPropertyListenerBlock(now, &address, .main, block)
        }
        device = now
        deviceListener = block
    }

    private func unwatchDevice() {
        if let device, let block = deviceListener {
            for selector in [Self.volumeSelector, kAudioDevicePropertyMute] {
                var address = Self.outputAddress(selector)
                guard AudioObjectHasProperty(device, &address) else { continue }
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, block)
            }
        }
        device = nil
        deviceListener = nil
    }
}
