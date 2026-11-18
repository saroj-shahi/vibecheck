import Darwin
import Foundation

enum MemoryPressure: Int {
    case normal = 1, warning = 2, critical = 4

    var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

struct MemorySample {
    var total: Double = Double(ProcessInfo.processInfo.physicalMemory)
    var app: Double = 0
    var wired: Double = 0
    var compressed: Double = 0
    var cached: Double = 0
    var free: Double = 0
    var pressure: MemoryPressure = .normal
    var swapUsed: Double = 0
    var swapTotal: Double = 0

    var used: Double { app + wired + compressed }
    var usage: Double { total > 0 ? min(1, used / total) : 0 }
}

final class MemoryMonitor {
    func sample() -> MemorySample {
        var result = MemorySample()
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if status == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            let purgeable = Double(stats.purgeable_count)
            result.app = max(0, Double(stats.internal_page_count) - purgeable) * page
            result.wired = Double(stats.wire_count) * page
            result.compressed = Double(stats.compressor_page_count) * page
            result.cached = (Double(stats.external_page_count) + purgeable) * page
            result.free = max(0, result.total - result.used - result.cached)
        }

        if let level = SysctlReader.int("kern.memorystatus_vm_pressure_level"),
           let pressure = MemoryPressure(rawValue: level) {
            result.pressure = pressure
        }

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            result.swapUsed = Double(swap.xsu_used)
            result.swapTotal = Double(swap.xsu_total)
        }
        return result
    }
}
