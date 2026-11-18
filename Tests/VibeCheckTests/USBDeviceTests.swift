import Foundation
import Testing
@testable import VibeCheck

struct USBDeviceTests {
    @Test func keepsNamedDevicesAndDropsHubs() {
        let entries: [(id: UInt64, properties: [String: Any])] = [
            (1, ["USB Product Name": "USB2.0 Hub", "bDeviceClass": 9]),
            (2, ["USB Product Name": "YubiKey OTP+FIDO+CCID", "USB Vendor Name": "Yubico", "bDeviceClass": 0]),
            (3, ["kUSBProductString": "Logitech Webcam C920", "kUSBVendorString": ""]),
            (4, ["bDeviceClass": 0]),                                 // no name
            (5, ["USB Product Name": "   "]),
        ]
        let devices = USBDeviceMonitor.filter(entries)
        #expect(devices.map(\.name) == ["Logitech Webcam C920", "YubiKey OTP+FIDO+CCID"])
        #expect(devices.map(\.vendor) == [nil, "Yubico"])
    }

    @Test func liveReadDoesNotCrash() {
        _ = USBDeviceMonitor.devices()   // empty on a Mac with nothing plugged in
    }
}
