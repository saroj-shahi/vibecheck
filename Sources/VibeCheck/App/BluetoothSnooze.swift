import AppKit
import CoreBluetooth

/// Turns Bluetooth off while the Mac sleeps and back on when it wakes (the idea from similar Bluetooth tools), so a
/// sleeping Mac doesn't grab headphones that are also paired with a phone.
///
/// Differences from similar Bluetooth tools, on purpose:
/// - Bluetooth is only turned back on if VibeCheck turned it off. If it was already off, it stays off.
/// - Nothing happens at shutdown: if VibeCheck didn't relaunch, the Mac would boot with Bluetooth off.
/// - The "we turned it off" marker is stored, so a crash or quit during sleep is repaired at next launch.
@MainActor
final class BluetoothSnooze {
    static let shared = BluetoothSnooze()

    /// Decisions, kept pure for tests.
    enum Policy {
        /// Turn Bluetooth off as the Mac goes to sleep?
        static func shouldPowerOff(enabled: Bool, poweredOn: Bool?) -> Bool {
            enabled && poweredOn == true
        }

        /// Turn Bluetooth on (at wake or launch)? Only if we were the ones who turned it off.
        static func shouldPowerOn(snoozedByUs: Bool) -> Bool { snoozedByUs }
    }

    /// Whether the feature is on; set by the app delegate from settings.
    var isEnabled: () -> Bool = { false }

    private let defaults = UserDefaults.standard
    private let markerKey = "bluetoothSnoozedBySleep"
    private var started = false

    private var snoozedByUs: Bool {
        get { defaults.bool(forKey: markerKey) }
        set { defaults.set(newValue, forKey: markerKey) }
    }

    /// False when the private calls are missing on this macOS (they are looked up at runtime).
    var isAvailable: Bool { Controller.getPower != nil && Controller.setPower != nil }

    /// Controller power right now; nil if the private call is missing or Bluetooth access isn't allowed
    /// (calling it without access makes macOS abort the process).
    var isPoweredOn: Bool? { access == .allowed ? Controller.isPoweredOn : nil }

    enum Access { case allowed, notAsked, denied }

    /// Bluetooth privacy permission, read without prompting.
    var access: Access {
        switch CBManager.authorization {
        case .allowedAlways: .allowed
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    private var permissionProbe: CBCentralManager?

    /// Shows the Bluetooth permission prompt (once). Called when the setting is switched on, so the
    /// prompt never appears as the Mac is going to sleep.
    func requestAccess() {
        guard access == .notAsked, permissionProbe == nil else { return }
        permissionProbe = CBCentralManager(delegate: nil, queue: nil)
    }

    func start() {
        guard !started else { return }
        started = true
        // Quit, crashed or force-restarted while asleep: put Bluetooth back.
        if Policy.shouldPowerOn(snoozedByUs: snoozedByUs) { powerOn(reason: "launch after an unfinished sleep") }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BluetoothSnooze.shared.willSleep() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BluetoothSnooze.shared.didWake() }
        }
    }

    private func willSleep() {
        guard Policy.shouldPowerOff(enabled: isEnabled(), poweredOn: isPoweredOn) else { return }
        snoozedByUs = true
        Controller.setPower?(0)
        NSLog("VibeCheck: Bluetooth off for sleep")
    }

    private func didWake() {
        guard Policy.shouldPowerOn(snoozedByUs: snoozedByUs) else { return }
        powerOn(reason: "wake")
    }

    private func powerOn(reason: String) {
        guard access == .allowed else { snoozedByUs = false; return }
        Controller.setPower?(1)
        snoozedByUs = false
        NSLog("VibeCheck: Bluetooth back on (\(reason))")
    }

    /// `IOBluetoothPreference{Get,Set}ControllerPowerState`: private but long-standing (similar tools).
    private enum Controller {
        private typealias GetFn = @convention(c) () -> Int32
        private typealias SetFn = @convention(c) (Int32) -> Void

        private nonisolated(unsafe) static let handle =
            dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_NOW)

        nonisolated(unsafe) static let getPower: (() -> Int32)? = {
            guard let handle, let symbol = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState") else { return nil }
            let fn = unsafeBitCast(symbol, to: GetFn.self)
            return { fn() }
        }()

        nonisolated(unsafe) static let setPower: ((Int32) -> Void)? = {
            guard let handle, let symbol = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState") else { return nil }
            let fn = unsafeBitCast(symbol, to: SetFn.self)
            return { fn($0) }
        }()

        static var isPoweredOn: Bool? { getPower.map { $0() == 1 } }
    }
}
