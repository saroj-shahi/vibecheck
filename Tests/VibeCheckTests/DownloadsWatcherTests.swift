import Foundation
import Testing
@testable import VibeCheck

struct DownloadsWatcherTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func entry(_ name: String, ago: TimeInterval) -> DownloadsWatcher.Entry {
        .init(name: name, modified: now.addingTimeInterval(-ago))
    }

    @Test func activeRules() {
        #expect(!DownloadsWatcher.isActive([], now: now))
        #expect(!DownloadsWatcher.isActive([entry("report.pdf", ago: 3600)], now: now))
        // Anything that just changed: curl, AirDrop, a copy.
        #expect(DownloadsWatcher.isActive([entry("report.pdf", ago: 2)], now: now))
        // Browser in-progress files count for longer, but not forever (a crash leaves them behind).
        #expect(DownloadsWatcher.isActive([entry("big.iso.crdownload", ago: 60)], now: now))
        #expect(DownloadsWatcher.isActive([entry("Movie.mp4.download", ago: 60)], now: now))
        #expect(DownloadsWatcher.isActive([entry("x.zip.PART", ago: 60)], now: now))
        #expect(!DownloadsWatcher.isActive([entry("big.iso.crdownload", ago: 600)], now: now))
        // Finder touching .DS_Store isn't a download.
        #expect(!DownloadsWatcher.isActive([entry(".DS_Store", ago: 1)], now: now))
    }

    @Test func scansARealFolder() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("vibecheck-downloads-\(UUID().uuidString)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        #expect(DownloadsWatcher.scan(folder).isEmpty)

        let old = Date().addingTimeInterval(-3600)
        let file = folder.appendingPathComponent("old.pdf")
        try Data("x".utf8).write(to: file)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: file.path)
        #expect(!DownloadsWatcher.isActive(DownloadsWatcher.scan(folder), now: Date()))

        // Safari: the bundle's own date is old, the file inside is growing.
        let bundle = folder.appendingPathComponent("Movie.mp4.download")
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("y".utf8).write(to: bundle.appendingPathComponent("Movie.mp4"))
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: bundle.path)
        let entries = DownloadsWatcher.scan(folder)
        #expect(entries.count == 2)
        #expect(DownloadsWatcher.isActive(entries, now: Date()))
    }

    @Test func missingFolderIsQuiet() {
        #expect(DownloadsWatcher.scan(URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")).isEmpty)
    }

    @Test func triggerWording() {
        #expect(AwakeTriggerAction.description(onPower: false, externalDisplay: false, downloading: true)
                == "while files are downloading")
        #expect(AwakeTriggerAction.description(onPower: true, externalDisplay: true, downloading: true)
                == "while plugged in, a display is connected and files are downloading")
    }
}
