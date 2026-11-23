import AppKit
import Foundation
import Observation

/// What an outside tool (an agent hook, a script) says it is doing. One JSON file per hook in
/// `~/.config/vibecheck/hooks/`; VibeCheck only reads them and never creates the folder.
enum VibeHookState: String, Sendable {
    case active, idle, needsInput = "needs_input", done, error

    /// Sort rank: needs_input first, then error, then active, then the rest.
    var rank: Int {
        switch self {
        case .needsInput: 0
        case .error: 1
        case .active: 2
        case .idle, .done: 3
        }
    }
}

struct VibeHook: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let value: String
    let state: VibeHookState
    /// A valid SF Symbol name, or nil (the pill draws a dot).
    let icon: String?
    let updatedAt: Date
    let ttl: TimeInterval
    let file: String

    var expiresAt: Date { updatedAt.addingTimeInterval(ttl) }
    func isLive(now: Date) -> Bool { expiresAt > now }
}

@Observable
@MainActor
final class VibeHooks {
    static let shared = VibeHooks(directory: VibeHooks.defaultDirectory)

    nonisolated static let maxFiles = 8
    nonisolated static let maxFileBytes = 4096
    nonisolated static let maxLabel = 24
    nonisolated static let maxValue = 32
    nonisolated static let ttlRange: ClosedRange<TimeInterval> = 5...86_400
    nonisolated static let defaultTTL: TimeInterval = 300
    nonisolated static let debounce: TimeInterval = 0.15

    nonisolated static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/vibecheck/hooks", isDirectory: true)
    }

    /// Live hooks, most urgent first.
    private(set) var hooks: [VibeHook] = []
    var needsInput: Bool { hooks.contains { $0.state == .needsInput } }

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var all: [VibeHook] = []
    @ObservationIgnored private var dirSource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var parentSource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var parentPath: String?
    @ObservationIgnored private var fileSources: [String: DispatchSourceFileSystemObject] = [:]
    @ObservationIgnored private var pending: DispatchWorkItem?
    @ObservationIgnored private var expiryTimer: Timer?
    @ObservationIgnored private var started = false

    init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
    }

    func start() {
        guard !started else { return }
        started = true
        reload()
    }

    func stop() {
        started = false
        pending?.cancel()
        expiryTimer?.invalidate()
        expiryTimer = nil
        dirSource?.cancel(); dirSource = nil
        parentSource?.cancel(); parentSource = nil; parentPath = nil
        fileSources.values.forEach { $0.cancel() }
        fileSources = [:]
    }

    // MARK: Watching

    private func eventReceived() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: item)
    }

    private func reload() {
        guard started else { return }
        all = Self.load(directory: directory, now: now())
        rewatch()
        publish()
    }

    /// Recomputes the live list from what's loaded, then re-arms the one expiry timer.
    private func publish() {
        let current = now()
        let live = Self.sorted(all.filter { $0.isLive(now: current) })
        if live != hooks { hooks = live }
        expiryTimer?.invalidate()
        expiryTimer = nil
        guard let due = Self.nextExpiry(all, now: current) else { return }
        let timer = Timer(timeInterval: max(0.05, due.timeIntervalSince(current)), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    private func rewatch() {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue {
            parentSource?.cancel(); parentSource = nil; parentPath = nil
            if dirSource == nil { dirSource = makeSource(path: directory.path, mask: [.write, .rename, .delete, .link]) }
            // A per-file source catches in-place writes that don't touch the directory entry.
            let names = Set(all.map(\.file))
            for (name, source) in fileSources where !names.contains(name) { source.cancel(); fileSources[name] = nil }
            for name in names where fileSources[name] == nil {
                fileSources[name] = makeSource(path: directory.appendingPathComponent(name).path,
                                               mask: [.write, .extend, .rename, .delete])
            }
        } else {
            dirSource?.cancel(); dirSource = nil
            fileSources.values.forEach { $0.cancel() }
            fileSources = [:]
            // Wait for the folder to appear: watch the nearest existing parent. Never create anything.
            var candidate = directory.deletingLastPathComponent()
            while candidate.path != "/", !fm.fileExists(atPath: candidate.path) { candidate = candidate.deletingLastPathComponent() }
            // Re-target as the path grows: always the nearest existing ancestor.
            guard parentPath != candidate.path else { return }
            parentSource?.cancel()
            parentSource = makeSource(path: candidate.path, mask: [.write, .rename, .delete, .link])
            parentPath = parentSource == nil ? nil : candidate.path
        }
    }

    private func makeSource(path: String, mask: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A deleted or renamed target leaves a dead descriptor: drop it so reload re-opens by path.
                if !source.data.intersection([.delete, .rename]).isEmpty { self.dropSource(source) }
                self.eventReceived()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func dropSource(_ source: DispatchSourceFileSystemObject) {
        if dirSource === source { dirSource?.cancel(); dirSource = nil }
        if parentSource === source { parentSource?.cancel(); parentSource = nil; parentPath = nil }
        for (name, s) in fileSources where s === source { s.cancel(); fileSources[name] = nil }
    }

    // MARK: Pure helpers

    /// Every valid hook file in `directory`: `*.json`, at most 8, at most 4 KB each, symlinks not followed.
    /// Includes expired ones (the caller filters), so the next expiry can be computed.
    nonisolated static func load(directory: URL, now: Date) -> [VibeHook] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        var result: [VibeHook] = []
        for name in names.filter({ $0.hasSuffix(".json") }).sorted().prefix(maxFiles) {
            guard let data = readSmallFile(directory.appendingPathComponent(name).path),
                  let hook = parse(data, file: name) else { continue }
            result.append(hook)
        }
        return dedupe(result)
    }

    nonisolated static func readSmallFile(_ path: String) -> Data? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= maxFileBytes else { return nil }
        var buffer = [UInt8](repeating: 0, count: maxFileBytes + 1)
        let n = read(fd, &buffer, maxFileBytes + 1)
        guard n >= 0, n <= maxFileBytes else { return nil }
        return Data(buffer.prefix(n))
    }

    nonisolated static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: text) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    /// nil for anything missing, wrongly typed or unknown (a bad state): the file is skipped silently.
    nonisolated static func parse(_ data: Data, file: String) -> VibeHook? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String, !id.isEmpty,
              let label = object["label"] as? String,
              let value = object["value"] as? String,
              let stateText = object["state"] as? String, let state = VibeHookState(rawValue: stateText),
              let updated = object["updatedAt"] as? String, let updatedAt = parseDate(updated)
        else { return nil }
        var ttl = defaultTTL
        if let raw = object["ttlSeconds"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            ttl = number.doubleValue
            guard ttl.isFinite else { return nil }
        }
        ttl = min(max(ttl, ttlRange.lowerBound), ttlRange.upperBound)
        var icon: String?
        if let name = object["icon"] as? String, !name.isEmpty, NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            icon = name
        }
        return VibeHook(id: id, label: String(label.prefix(maxLabel)), value: String(value.prefix(maxValue)),
                        state: state, icon: icon, updatedAt: updatedAt, ttl: ttl, file: file)
    }

    /// One hook per id: the newest updatedAt wins (ties: the later file name).
    nonisolated static func dedupe(_ hooks: [VibeHook]) -> [VibeHook] {
        var best: [String: VibeHook] = [:]
        for hook in hooks {
            if let existing = best[hook.id], existing.updatedAt > hook.updatedAt { continue }
            best[hook.id] = hook
        }
        var seen = Set<String>()
        return hooks.filter { best[$0.id]?.file == $0.file && seen.insert($0.id).inserted }
    }

    /// needs_input, error, active, then the rest; newest first within each.
    nonisolated static func sorted(_ hooks: [VibeHook]) -> [VibeHook] {
        dedupe(hooks).sorted {
            if $0.state.rank != $1.state.rank { return $0.state.rank < $1.state.rank }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    /// The soonest moment a still-live hook expires, or nil when nothing is live.
    nonisolated static func nextExpiry(_ hooks: [VibeHook], now: Date) -> Date? {
        hooks.filter { $0.isLive(now: now) }.map(\.expiresAt).min()
    }
}
