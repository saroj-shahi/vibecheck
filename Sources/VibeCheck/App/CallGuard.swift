import AppKit
import CoreAudio
import CoreMediaIO

/// Reads whether any camera or microphone is running in any app. These queries need no privacy permission.
enum CallDetector {
    /// True when a camera or a microphone is in use somewhere. Blocking; call off the main thread.
    nonisolated static func mediaInUse() -> Bool { cameraInUse() || microphoneInUse() }

    nonisolated static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0,
              size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used = size
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == 0
        else { return false }
        for device in devices {
            var running: UInt32 = 0
            let runSize = UInt32(MemoryLayout<UInt32>.size)
            var runAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var runUsed = runSize
            if CMIOObjectGetPropertyData(device, &runAddress, 0, nil, runSize, &runUsed, &running) == 0, running != 0 {
                return true
            }
        }
        return false
    }

    nonisolated static func microphoneInUse() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == 0,
              size > 0 else { return false }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == 0
        else { return false }
        for device in devices where hasInput(device) {
            var running: UInt32 = 0
            var runSize = UInt32(MemoryLayout<UInt32>.size)
            var runAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                        mScope: kAudioObjectPropertyScopeGlobal,
                                                        mElement: kAudioObjectPropertyElementMain)
            if AudioObjectGetPropertyData(device, &runAddress, 0, nil, &runSize, &running) == 0, running != 0 { return true }
        }
        return false
    }

    private nonisolated static func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == 0 && size > 0
    }
}

/// Debounce for the call signal: a call starts after a few polls in a row with the camera or mic in use,
/// and ends after a few without, so a short blip doesn't hold alerts or flip keep-awake.
struct CallState: Equatable {
    private(set) var inCall = false
    private var streak = 0
    static let startPolls = 2, endPolls = 3

    /// Feeds one poll; returns true when `inCall` changed.
    @discardableResult
    mutating func update(detected: Bool) -> Bool {
        if detected == inCall { streak = 0; return false }
        streak += 1
        guard streak >= (inCall ? Self.endPolls : Self.startPolls) else { return false }
        inCall = detected
        streak = 0
        return true
    }
}

/// Call guard: while the camera or mic is in use it holds non-critical alerts until the call ends, keeps
/// the display awake (through `KeepAwake`), and warns once per call when one app is heavy enough to stutter it.
@MainActor
final class CallGuard {
    static let shared = CallGuard()

    private(set) var inCall = false
    private var state = CallState()
    private var polling = false
    private var warned = false
    private var lastPoll = Date.distantPast
    /// Replaceable for tests; runs off the main thread.
    nonisolated(unsafe) var detector: @Sendable () -> Bool = { CallDetector.mediaInUse() }

    /// An app at or above this (percent of one core) is worth a warning.
    nonisolated static let heavyCPU = 100.0
    /// Call apps themselves: quitting one would end the call it is warning about.
    nonisolated static let callApps: Set<String> = [
        "zoom.us", "us.zoom.xos", "Microsoft Teams", "Teams", "FaceTime", "Slack", "Discord", "Webex", "Skype",
        "WhatsApp", "Tuple", "Around", "Google Meet", "Signal", "Telegram", "Loom", "OBS", "Zoom Workplace",
    ]

    /// The busiest app that is heavy enough to warn about; nil if none (or it is a call app, VibeCheck or protected).
    nonisolated static func heavyApp(_ apps: [AppUsage], ownPID: Int32, threshold: Double = heavyCPU) -> AppUsage? {
        apps.filter { $0.cpu >= threshold && $0.id != ownPID && !callApps.contains($0.name)
                      && !ProcessKiller.protectedNames.contains($0.name) }
            .max { $0.cpu < $1.cpu }
    }

    nonisolated static func warning(name: String, cpu: Double) -> (title: String, body: String) {
        (String(localized: "\(name) is at \(Int(cpu.rounded()))% CPU"), String(localized: "It could make your call stutter. Quit \(name)?"))
    }

    /// Called once per stats tick.
    func tick(stats: SystemStats, alerts: AlertEngine, now: Date = Date()) {
        guard AppSettings.shared.callGuardEnabled else {
            if inCall { setInCall(false) }
            state = CallState()
            warned = false
            return
        }
        poll(now: now)
        guard inCall, !warned,
              let app = Self.heavyApp(stats.topApps(by: \.cpu, limit: 3), ownPID: ProcessInfo.processInfo.processIdentifier),
              ProcessKiller.protectionReason(pid: app.id) == nil,
              let target = ProcessKiller.identity(of: app.id) else { return }
        warned = true
        let text = Self.warning(name: app.name, cpu: app.cpu)
        alerts.notifyWithQuit(title: text.title, body: text.body, appName: app.name, target: target)
    }

    /// Reads the devices off the main thread; applies the result on the next hop.
    private func poll(now: Date) {
        guard !polling, now.timeIntervalSince(lastPoll) >= 1 else { return }
        polling = true
        lastPoll = now
        let detect = detector
        Task.detached {
            let detected = detect()
            await MainActor.run {
                let guardRef = CallGuard.shared
                guardRef.polling = false
                guard AppSettings.shared.callGuardEnabled else { return }
                if guardRef.state.update(detected: detected) { guardRef.setInCall(guardRef.state.inCall) }
            }
        }
    }

    private func setInCall(_ value: Bool) {
        inCall = value
        if !value { warned = false }
        NSLog("%@", "VibeCheck call guard: \(value ? "call started" : "call ended")")
        KeepAwake.shared.check()
    }
}
