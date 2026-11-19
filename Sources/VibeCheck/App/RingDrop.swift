import AppKit
import Observation

/// What dropping something on the ring does.
enum RingDropAction: Equatable {
    case keepAwake(AwakeEnd)

    /// An app keeps the Mac awake while it runs; any other file or folder while it keeps changing.
    nonisolated static func action(for url: URL, bundleID: String?, displayName: String) -> RingDropAction {
        if url.pathExtension.lowercased() == "app", let bundleID {
            return .keepAwake(.whileRunning(bundleID: bundleID, name: displayName))
        }
        return .keepAwake(.whileChanging(path: url.path, name: displayName))
    }

    @MainActor
    static func action(for url: URL) -> RingDropAction {
        action(for: url, bundleID: Bundle(url: url)?.bundleIdentifier,
               displayName: FileManager.default.displayName(atPath: url.path))
    }
}

/// True while a drag hovers over the ring; the label dilates by `scale`.
@Observable
@MainActor
final class RingDropState {
    var isTargeted = false
    static let scale: CGFloat = 1.1
}

/// Transparent view over the status button that accepts file drops. Clicks are handed on to the button.
final class RingDropView: NSView {
    let state: RingDropState
    let onDrop: ([URL]) -> Void

    init(state: RingDropState, onDrop: @escaping ([URL]) -> Void) {
        self.state = state
        self.onDrop = onDrop
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseDown(with event: NSEvent) { (superview as? NSControl)?.mouseDown(with: event) ?? super.mouseDown(with: event) }

    private func urls(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !urls(sender).isEmpty else { return [] }
        MainActor.assumeIsolated { state.isTargeted = true }
        return .generic
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { MainActor.assumeIsolated { state.isTargeted = false } }
    override func draggingEnded(_ sender: NSDraggingInfo) { MainActor.assumeIsolated { state.isTargeted = false } }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        MainActor.assumeIsolated { state.isTargeted = false }
        let dropped = urls(sender)
        guard !dropped.isEmpty else { return false }
        MainActor.assumeIsolated { onDrop(dropped) }
        return true
    }
}
