import Foundation
import Testing
@testable import VibeCheck

struct RingDropAndNotchHideTests {
    @Test func appDropFollowsTheApp() {
        let action = RingDropAction.action(for: URL(fileURLWithPath: "/Applications/Safari.app"),
                                           bundleID: "com.apple.Safari", displayName: "Safari")
        #expect(action == .keepAwake(.whileRunning(bundleID: "com.apple.Safari", name: "Safari")))
    }

    @Test func fileDropFollowsTheFile() {
        let action = RingDropAction.action(for: URL(fileURLWithPath: "/tmp/big.zip"), bundleID: nil, displayName: "big.zip")
        #expect(action == .keepAwake(.whileChanging(path: "/tmp/big.zip", name: "big.zip")))
    }

    @Test func changingPathEndsWhenQuiet() {
        let start = Date(timeIntervalSince1970: 1000)
        let session = AwakeSession(started: start, end: .whileChanging(path: "/x", name: "x"))
        func reason(_ now: TimeInterval, last: TimeInterval?) -> AwakeEndReason? {
            AwakeSession.endReason(session, now: start.addingTimeInterval(now), battery: BatterySample(), batteryFloor: 0,
                                   isRunning: { _ in true },
                                   lastChange: { _ in last.map { start.addingTimeInterval($0) } })
        }
        #expect(reason(5, last: nil) == nil)          // grace right after the drop
        #expect(reason(11, last: nil) == .fileDone)
        #expect(reason(30, last: 25) == nil)          // still being written
        #expect(reason(36, last: 25) == .fileDone)
    }

    @Test func newestModificationSeesNestedFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ringdrop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        try "hi".write(to: file, atomically: true, encoding: .utf8)
        let future = Date().addingTimeInterval(500)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: file.path)
        let found = try #require(PathActivity.newestModification(dir))
        #expect(abs(found.timeIntervalSince(future)) < 1)
        #expect(PathActivity.newestModification(dir.appendingPathComponent("nope")) == nil)
    }

    @Test func hiddenDetection() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let left = NSRect(x: 0, y: 950, width: 656, height: 32), right = NSRect(x: 856, y: 950, width: 656, height: 32)
        func hidden(_ x: CGFloat) -> Bool {
            NotchFit.isHidden(itemRect: NSRect(x: x, y: 950, width: 40, height: 24), screenFrame: screen,
                              notchLeft: left, notchRight: right)
        }
        #expect(hidden(700))
        #expect(hidden(-100))
        #expect(!hidden(1000))
        #expect(!NotchFit.isHidden(itemRect: NSRect(x: 700, y: 0, width: 40, height: 24), screenFrame: screen,
                                   notchLeft: nil, notchRight: nil))
    }

    @Test func hideWatchDebounces() {
        var watch = NotchHideWatch()
        let t = Date(timeIntervalSince1970: 0)
        let first = watch.update(hidden: true, now: t)
        let second = watch.update(hidden: true, now: t.addingTimeInterval(5))
        let flap = watch.update(hidden: false, now: t.addingTimeInterval(6))     // flap resets
        let again = watch.update(hidden: true, now: t.addingTimeInterval(7))
        let held = watch.update(hidden: true, now: t.addingTimeInterval(16))
        #expect(!first && !second && !flap && !again)
        #expect(held)
        #expect(NotchHideWatch.mayCollapse(separate: true, autoFit: true, optedOut: false))
        #expect(!NotchHideWatch.mayCollapse(separate: true, autoFit: true, optedOut: true))
        #expect(!NotchHideWatch.mayCollapse(separate: false, autoFit: true, optedOut: false))
    }
}
