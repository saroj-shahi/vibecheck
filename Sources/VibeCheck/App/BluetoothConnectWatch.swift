import Foundation
import IOBluetooth
import CoreBluetooth

/// When accessory batteries are looked up (pure, so it can be tested).
enum DeviceRefreshPolicy {
    enum Mode: Equatable {
        /// Nothing needs accessory levels.
        case off
        /// Refresh when the view opens and when a device connects or disconnects; no timer.
        case eventOnly
        /// Also refresh on this interval (seconds).
        case poll(TimeInterval)
    }

    static let slowPoll: TimeInterval = 600       // an alert rule is on: levels drain slowly
    static let fallbackPoll: TimeInterval = 60    // no Bluetooth permission: no connect events, so poll
    static let debounce: TimeInterval = 3
    static let lateRefresh: TimeInterval = 20     // levels often show up a while after connecting

    /// `eventsAvailable`: the Bluetooth permission is granted, so connect / disconnect notifications are registered.
    static func mode(viewOpen: Bool, alertRuleOn: Bool, eventsAvailable: Bool) -> Mode {
        guard viewOpen || alertRuleOn else { return .off }
        guard eventsAvailable else { return .poll(fallbackPoll) }
        return alertRuleOn ? .poll(slowPoll) : .eventOnly
    }

    /// Whether a poll is due. Event-only and off never are.
    static func pollDue(_ mode: Mode, lastFetch: Date?, now: Date) -> Bool {
        guard case .poll(let interval) = mode else { return false }
        return lastFetch.map { now.timeIntervalSince($0) >= interval } ?? true
    }

    /// Notifications are registered only with the Bluetooth permission already granted: IOBluetooth is
    /// the framework behind the permission prompt, and VibeCheck never asks for it just for this.
    static func permissionAllowed() -> Bool { CBManager.authorization == .allowedAlways }
}

/// Reports Bluetooth device connects and disconnects (IOBluetooth notifications), debounced by the caller.
@MainActor
final class BluetoothConnectWatch: NSObject {
    var onChange: (() -> Void)?
    private var connectToken: IOBluetoothUserNotification?
    private var disconnectTokens: [String: IOBluetoothUserNotification] = [:]
    private(set) var isWatching = false

    /// Registers once, and only when the permission is already granted. Returns whether it is watching.
    @discardableResult
    func startIfAllowed() -> Bool {
        if isWatching { return true }
        guard DeviceRefreshPolicy.permissionAllowed() else { return false }
        isWatching = true
        connectToken = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] where device.isConnected() {
            watchDisconnect(device)
        }
        return true
    }

    func stop() {
        connectToken?.unregister()
        connectToken = nil
        disconnectTokens.values.forEach { $0.unregister() }
        disconnectTokens = [:]
        isWatching = false
    }

    private func watchDisconnect(_ device: IOBluetoothDevice) {
        guard let address = device.addressString, disconnectTokens[address] == nil else { return }
        disconnectTokens[address] = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
    }

    @objc nonisolated private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // The device is registered on the main run loop's thread (where IOBluetooth delivers), so this is safe.
        nonisolated(unsafe) let device = device
        MainActor.assumeIsolated {
            watchDisconnect(device)
            onChange?()
        }
    }

    @objc nonisolated private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString
        MainActor.assumeIsolated {
            if let address { disconnectTokens[address]?.unregister(); disconnectTokens[address] = nil }
            onChange?()
        }
    }
}
