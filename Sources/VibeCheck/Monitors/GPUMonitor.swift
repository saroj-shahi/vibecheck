import Foundation
import IOKit

struct GPUInfo: Identifiable {
    let id: Int
    var model: String
    var cores: Int?
    var device: Double = 0     // overall utilization, 0...1
    var renderer: Double?      // Apple GPUs: fragment/compute share
    var tiler: Double?         // Apple GPUs: vertex/geometry share
    var memoryInUse: Double?   // bytes
    var memoryAllocated: Double?
}

struct GPUSample {
    var gpus: [GPUInfo] = []
    /// The busiest GPU drives the menu bar number.
    var utilization: Double { gpus.map(\.device).max() ?? 0 }
}

/// Reads `PerformanceStatistics` from every IOAccelerator (one per GPU; Intel Macs may have two).
enum GPUMonitor {
    static func sample() -> GPUSample {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return GPUSample() }
        defer { IOObjectRelease(iterator) }

        var gpus: [GPUInfo] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let info = read(service, index: gpus.count) { gpus.append(info) }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return GPUSample(gpus: gpus)
    }

    private static func read(_ service: io_object_t, index: Int) -> GPUInfo? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any],
              let stats = dict["PerformanceStatistics"] as? [String: Any] else { return nil }

        func percent(_ key: String) -> Double? {
            (stats[key] as? NSNumber).map { min(1, max(0, $0.doubleValue / 100)) }
        }
        func bytes(_ key: String) -> Double? { (stats[key] as? NSNumber)?.doubleValue }

        var info = GPUInfo(id: index, model: modelName(service, dict) ?? "GPU \(index + 1)")
        info.cores = (dict["gpu-core-count"] as? NSNumber)?.intValue
        info.device = percent("Device Utilization %") ?? percent("GPU Activity(%)") ?? 0
        info.renderer = percent("Renderer Utilization %")
        info.tiler = percent("Tiler Utilization %")
        info.memoryInUse = bytes("In use system memory") ?? bytes("vramUsedBytes")
        info.memoryAllocated = bytes("Alloc system memory")
        return info
    }

    /// Apple GPUs put "model" on the accelerator; discrete/Intel GPUs keep it on the parent PCI device.
    private static func modelName(_ service: io_object_t, _ dict: [String: Any]) -> String? {
        if let model = dict["model"] as? String { return model }
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(parent) }
        guard let value = IORegistryEntryCreateCFProperty(parent, "model" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return nil }
        if let data = value as? Data {
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
        }
        return value as? String
    }
}
