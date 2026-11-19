import Foundation
import IOKit

/// One external USB device (hubs left out).
struct USBDevice: Identifiable, Equatable, Sendable {
    let id: UInt64          // IORegistry entry id
    let name: String
    let vendor: String?
}

/// Connected USB devices from the IORegistry (`IOUSBHostDevice`). Read on demand, only while the
/// Battery view is open; a read takes a few milliseconds.
enum USBDeviceMonitor {
    static func devices() -> [USBDevice] {
        guard let matching = IOServiceMatching("IOUSBHostDevice") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var entries: [(id: UInt64, properties: [String: Any])] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &id)
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { continue }
            entries.append((id, properties))
        }
        return filter(entries)
    }

    /// Pure: named, non-hub devices, sorted by name. Class 9 is a hub.
    static func filter(_ entries: [(id: UInt64, properties: [String: Any])]) -> [USBDevice] {
        entries.compactMap { entry -> USBDevice? in
            let p = entry.properties
            if (p["bDeviceClass"] as? NSNumber)?.intValue == 9 { return nil }
            let name = (p["USB Product Name"] as? String) ?? (p["kUSBProductString"] as? String)
            guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let vendor = (p["USB Vendor Name"] as? String) ?? (p["kUSBVendorString"] as? String)
            return USBDevice(id: entry.id, name: name, vendor: vendor?.isEmpty == false ? vendor : nil)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
