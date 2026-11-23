import Darwin
import Foundation
import IOKit

/// Average power over a sampling window. A nil part means it couldn't be read (no placeholder zeros).
struct PowerReport: Equatable {
    var cpu: Double?
    var gpu: Double?
    var ane: Double?

    /// "3.2 W" (one decimal; whole watts from 10 W up).
    nonisolated static func label(_ watts: Double) -> String {
        watts < 9.95 ? String(format: "%.1f W", watts) : String(format: "%.0f W", watts)
    }

    /// Drops readings the OS can't be trusted for. A CPU delta of exactly 0 while the CPU is busy
    /// (>= 5%) means the energy counters are zeroed for us, so CPU and ANE are hidden, and stay hidden
    /// once `zeroed` is set so rows don't flicker.
    nonisolated static func trusted(_ report: PowerReport, cpuBusy: Double?, zeroed: Bool) -> (report: PowerReport, zeroed: Bool) {
        var zeroed = zeroed
        if !zeroed, report.cpu == 0, let busy = cpuBusy, busy >= 0.05 { zeroed = true }
        // A Mac chip doesn't draw this much; a reading like 186 W means the channel is garbage on this OS.
        if let cpu = report.cpu, cpu > plausibleCeiling { zeroed = true }
        var out = report
        if let gpu = out.gpu, gpu > plausibleCeiling { out.gpu = nil }
        guard zeroed else { return (out, false) }
        out.cpu = nil
        out.ane = nil
        return (out, true)
    }

    /// Watts above which a CPU or GPU reading can't be real (well above any Apple chip's draw).
    static let plausibleCeiling: Double = 150

    var isEmpty: Bool { cpu == nil && gpu == nil && ane == nil }

    /// Joules per unit label ("mJ", "uJ", "nJ"); nil for anything else.
    nonisolated static func joulesPerUnit(_ label: String) -> Double? {
        switch label.trimmingCharacters(in: .whitespaces) {
        case "J": 1
        case "mJ": 1e-3
        case "uJ", "µJ", "μJ": 1e-6
        case "nJ": 1e-9
        default: nil
        }
    }

    /// Watts from an energy delta, its unit label and the window length.
    nonisolated static func watts(delta: Int64, unit: String, seconds: Double) -> Double? {
        guard seconds > 0, delta >= 0, let scale = joulesPerUnit(unit) else { return nil }
        return Double(delta) * scale / seconds
    }

    struct Channel {
        var name: String
        var unit: String
        var value: Int64
    }

    /// Sums the Energy Model channels per component. A component with no readable channel stays nil.
    nonisolated static func report(from channels: [Channel], seconds: Double) -> PowerReport {
        var cpu: Double?, gpu: Double?, ane: Double?, gpuPlain: Double?
        func add(_ total: inout Double?, _ channel: Channel) {
            guard let w = watts(delta: channel.value, unit: channel.unit, seconds: seconds) else { return }
            total = (total ?? 0) + w
        }
        for channel in channels {
            let name = channel.name
            if name.hasSuffix("CPU Energy") { add(&cpu, channel) }
            else if name.hasSuffix("GPU Energy") { add(&gpu, channel) }
            else if name == "GPU" { add(&gpuPlain, channel) } // same energy under another name: fallback only
            else if name.hasPrefix("ANE") { add(&ane, channel) }
        }
        return PowerReport(cpu: cpu, gpu: gpu ?? gpuPlain, ane: ane)
    }
}

/// Reads the Energy Model through the private IOReport library, in user space (no sudo).
/// Every symbol is looked up at runtime; if any is missing, `sample()` returns nil.
final class PowerSampler {
    private typealias CopyChannelsInGroup = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias CreateSubscription = @convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> UnsafeRawPointer?
    private typealias CreateSamples = @convention(c) (UnsafeRawPointer, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateSamplesDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias ChannelGetString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias SimpleValue = @convention(c) (CFDictionary, UnsafeMutablePointer<Int32>?) -> Int64

    private struct API {
        let copyChannels: CopyChannelsInGroup
        let createSubscription: CreateSubscription
        let createSamples: CreateSamples
        let createDelta: CreateSamplesDelta
        let channelName: ChannelGetString
        let unitLabel: ChannelGetString
        let simpleValue: SimpleValue
    }

    private var api: API?
    private var subscription: UnsafeRawPointer?
    private var subscribed: CFMutableDictionary?
    private var previous: (sample: CFDictionary, time: Date)?
    private var loaded = false
    /// Set once the OS has shown zeroed CPU energy; kept for the rest of the subscription.
    private var cpuZeroed = false

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return }
        func sym<T>(_ name: String, as _: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let copyChannels = sym("IOReportCopyChannelsInGroup", as: CopyChannelsInGroup.self),
              let createSubscription = sym("IOReportCreateSubscription", as: CreateSubscription.self),
              let createSamples = sym("IOReportCreateSamples", as: CreateSamples.self),
              let createDelta = sym("IOReportCreateSamplesDelta", as: CreateSamplesDelta.self),
              let channelName = sym("IOReportChannelGetChannelName", as: ChannelGetString.self),
              let unitLabel = sym("IOReportChannelGetUnitLabel", as: ChannelGetString.self),
              let simpleValue = sym("IOReportSimpleGetIntegerValue", as: SimpleValue.self),
              let channels = copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue()
        else { return }
        var subbed: Unmanaged<CFMutableDictionary>?
        guard let sub = createSubscription(nil, channels, &subbed, 0, nil), let subbed else { return }
        subscription = sub
        subscribed = subbed.takeRetainedValue()
        api = API(copyChannels: copyChannels, createSubscription: createSubscription, createSamples: createSamples,
                  createDelta: createDelta, channelName: channelName, unitLabel: unitLabel, simpleValue: simpleValue)
    }

    /// Average power since the previous call. The first call only primes the baseline and returns nil.
    func sample(cpuBusy: Double?) -> PowerReport? {
        load()
        guard let api, let subscription, let subscribed,
              let now = api.createSamples(subscription, subscribed, nil)?.takeRetainedValue() else { return nil }
        let time = Date()
        defer { previous = (now, time) }
        guard let previous, let delta = api.createDelta(previous.sample, now, nil)?.takeRetainedValue(),
              let items = (delta as NSDictionary)["IOReportChannels"] as? [NSDictionary] else { return nil }
        let seconds = time.timeIntervalSince(previous.time)
        var channels: [PowerReport.Channel] = []
        for item in items {
            let dict = item as CFDictionary
            guard let name = api.channelName(dict)?.takeUnretainedValue() as String?,
                  let unit = api.unitLabel(dict)?.takeUnretainedValue() as String? else { continue }
            var status: Int32 = 0
            let value = api.simpleValue(dict, &status)
            guard status == 0 else { continue }
            channels.append(.init(name: name, unit: unit, value: value))
        }
        let checked = PowerReport.trusted(PowerReport.report(from: channels, seconds: seconds),
                                          cpuBusy: cpuBusy, zeroed: cpuZeroed)
        cpuZeroed = checked.zeroed
        let report = checked.report
        return report.isEmpty ? nil : report
    }

    /// Drops the baseline and releases the subscription; the next `sample` re-subscribes lazily.
    /// `cpuZeroed` is kept so CPU/ANE don't reappear after a re-subscribe.
    func reset() {
        previous = nil
        subscribed = nil
        if let subscription { Unmanaged<CFTypeRef>.fromOpaque(subscription).release() }
        subscription = nil
        loaded = false
    }
}

/// Which logical CPUs are performance ("P") or efficiency ("E") cores, from the IORegistry.
enum CoreClusters {
    /// Parses `cluster-type` ("E"/"P" as data or string, possibly NUL-terminated) and `logical-cpu-id`
    /// from registry property dictionaries. Entries that lack either are skipped.
    nonisolated static func parse(_ entries: [[String: Any]]) -> [Int: Character] {
        var map: [Int: Character] = [:]
        for entry in entries {
            guard let id = (entry["logical-cpu-id"] as? NSNumber)?.intValue ?? dataInt(entry["logical-cpu-id"]),
                  let type = typeLetter(entry["cluster-type"]) else { continue }
            map[id] = type
        }
        return map
    }

    private nonisolated static func dataInt(_ value: Any?) -> Int? {
        guard let data = value as? Data, !data.isEmpty, data.count <= 4 else { return nil }
        return data.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
    }

    private nonisolated static func typeLetter(_ value: Any?) -> Character? {
        let raw: String?
        if let data = value as? Data { raw = String(decoding: data.filter { $0 != 0 }, as: UTF8.self) }
        else { raw = value as? String }
        guard let c = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().first,
              c == "E" || c == "P" else { return nil }
        return c
    }

    /// Average busy fraction of each group. Nil unless the map covers every core and both groups exist.
    nonisolated static func averages(perCore: [Double], map: [Int: Character]) -> (p: Double, e: Double)? {
        guard !perCore.isEmpty, perCore.indices.allSatisfy({ map[$0] != nil }) else { return nil }
        let p = perCore.indices.filter { map[$0] == "P" }.map { perCore[$0] }
        let e = perCore.indices.filter { map[$0] == "E" }.map { perCore[$0] }
        guard !p.isEmpty, !e.isEmpty else { return nil }
        return (p.reduce(0, +) / Double(p.count), e.reduce(0, +) / Double(e.count))
    }

    /// Reads the map from the live registry: the children of `/cpus` in the device tree carry
    /// `cluster-type` and `logical-cpu-id`. Empty on Intel or if nothing matches.
    static func read() -> [Int: Character] {
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != 0 else { return [:] }
        defer { IOObjectRelease(cpus) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        var entries: [[String: Any]] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] { entries.append(dict) }
            IOObjectRelease(service)
        }
        return parse(entries)
    }
}
