import Foundation
import IOKit

struct VolumeInfo: Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let total: Double
    let available: Double
    var used: Double { max(0, total - available) }
    var usage: Double { total > 0 ? used / total : 0 }
}

struct DiskSample {
    var readRate: Double = 0
    var writeRate: Double = 0
}

final class DiskMonitor {
    private var lastRead: UInt64 = 0
    private var lastWrite: UInt64 = 0
    private var lastTime: Date?

    func sample() -> DiskSample {
        let (read, write) = Self.blockStorageCounters()
        let now = Date()
        var result = DiskSample()
        if let lastTime, read >= lastRead, write >= lastWrite {
            let elapsed = max(now.timeIntervalSince(lastTime), 0.001)
            result.readRate = Double(read - lastRead) / elapsed
            result.writeRate = Double(write - lastWrite) / elapsed
        }
        lastRead = read; lastWrite = write; lastTime = now
        return result
    }

    private static func blockStorageCounters() -> (UInt64, UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0, write: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString,
                                                           kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                read &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return (read, write)
    }

    static func volumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeAvailableCapacityKey, .volumeIsBrowsableKey,
                                      .volumeIsLocalKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                               options: [.skipHiddenVolumes]) else { return [] }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable == true,
                  values.volumeIsLocal == true,
                  let total = values.volumeTotalCapacity, total > 0 else { return nil }
            let available = values.volumeAvailableCapacityForImportantUsage.map(Double.init)
                ?? values.volumeAvailableCapacity.map(Double.init) ?? 0
            return VolumeInfo(path: url.path, name: values.volumeName ?? url.lastPathComponent,
                              total: Double(total), available: available)
        }
    }
}
