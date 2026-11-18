import Testing
@testable import VibeCheck

@MainActor
struct BluetoothSnoozeTests {
    @Test func powersOffOnlyWhenEnabledAndOn() {
        #expect(BluetoothSnooze.Policy.shouldPowerOff(enabled: true, poweredOn: true))
        #expect(!BluetoothSnooze.Policy.shouldPowerOff(enabled: false, poweredOn: true))
        #expect(!BluetoothSnooze.Policy.shouldPowerOff(enabled: true, poweredOn: false)) // already off: leave it
        #expect(!BluetoothSnooze.Policy.shouldPowerOff(enabled: true, poweredOn: nil))   // API missing
    }

    @Test func powersOnOnlyIfWeTurnedItOff() {
        #expect(BluetoothSnooze.Policy.shouldPowerOn(snoozedByUs: true))
        #expect(!BluetoothSnooze.Policy.shouldPowerOn(snoozedByUs: false))
    }

    /// Read-only: resolves the private calls, never changes the power state.
    @Test func privateCallsResolveOnThisMac() {
        #expect(BluetoothSnooze.shared.isAvailable)
    }
}
