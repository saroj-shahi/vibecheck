import AppKit
import SwiftUI

/// "Find my cursor": a click-through ring closes in on the pointer and fades (0.8 s; a plain fade with
/// Reduce Motion). One borderless panel on the pointer's screen; no permissions.
@MainActor
enum CursorFinder {
    private static var panel: NSPanel?
    static let size: CGFloat = 160

    static func flash() {
        panel?.orderOut(nil)
        let point = NSEvent.mouseLocation
        let panel = NSPanel(contentRect: NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: CursorRing())
        panel.orderFrontRegardless()
        self.panel = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            if self.panel === panel { panel.orderOut(nil); self.panel = nil }
        }
    }
}

private struct CursorRing: View {
    @State private var landed = false
    @State private var faded = false

    var body: some View {
        let reduce = Deck.reduceMotion
        Circle()
            .strokeBorder(Color.accentColor, lineWidth: 4)
            .background(Circle().fill(Color.accentColor.opacity(0.18)))
            .frame(width: 56, height: 56)
            .scaleEffect(reduce || landed ? 1 : 2.4)
            .opacity(faded ? 0 : 1)
            .frame(width: CursorFinder.size, height: CursorFinder.size)
            .onAppear {
                withAnimation(.easeOut(duration: 0.45)) { landed = true }
                withAnimation(.easeIn(duration: reduce ? 0.8 : 0.3).delay(reduce ? 0 : 0.5)) { faded = true }
            }
            .accessibilityHidden(true)
    }
}
