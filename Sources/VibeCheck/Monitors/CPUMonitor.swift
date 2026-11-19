import Darwin
import Foundation

struct CPUSample {
    var user: Double = 0
    var system: Double = 0
    var idle: Double = 1
    var perCore: [Double] = []
    var total: Double { min(1, user + system) }
}

/// Reads per-core tick counters from the Mach host and turns deltas into usage fractions.
final class CPUMonitor {
    private var previous: [[UInt32]] = []

    let performanceCores = SysctlReader.int("hw.perflevel0.logicalcpu") ?? 0
    let efficiencyCores = SysctlReader.int("hw.perflevel1.logicalcpu") ?? 0
    let modelName: String = SysctlReader.string("machdep.cpu.brand_string") ?? "CPU"

    func sample() -> CPUSample? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        var current: [[UInt32]] = []
        current.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            let base = Int(CPU_STATE_MAX) * core
            current.append([
                UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]),
            ])
        }

        let prev = previous
        previous = current
        guard prev.count == current.count else { return nil }

        var sumUser = 0.0, sumSystem = 0.0, sumIdle = 0.0
        var perCore: [Double] = []
        for (now, before) in zip(current, prev) {
            let user = Double(now[0] &- before[0]) + Double(now[3] &- before[3])
            let system = Double(now[1] &- before[1])
            let idle = Double(now[2] &- before[2])
            let total = user + system + idle
            perCore.append(total > 0 ? (user + system) / total : 0)
            sumUser += user; sumSystem += system; sumIdle += idle
        }
        let all = sumUser + sumSystem + sumIdle
        guard all > 0 else { return nil }
        return CPUSample(user: sumUser / all, system: sumSystem / all,
                         idle: sumIdle / all, perCore: perCore)
    }

    static func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) == 3 ? loads : [0, 0, 0]
    }
}

enum SysctlReader {
    static func int(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        // Some keys are 32-bit; the low bytes are correct on little-endian either way.
        return size == 4 ? Int(Int32(truncatingIfNeeded: value)) : Int(value)
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cBuffer: buffer)
    }

    static func uptime() -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return 0 }
        return Date().timeIntervalSince1970 - Double(boot.tv_sec)
    }
}
