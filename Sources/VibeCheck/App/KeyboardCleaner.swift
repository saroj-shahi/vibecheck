import AppKit
import Observation
import SwiftUI

/// Keyboard cleaning mode: swallows key, modifier and media-key events for 45 s with a countdown overlay.
/// "Done" on the overlay (the mouse still works) ends it early. Needs Accessibility for the event tap.
/// It can't block Touch ID or the power key (handled below the event system); the overlay says so.
@Observable
@MainActor
final class KeyboardCleaner {
    static let shared = KeyboardCleaner()
    nonisolated static let duration = 45
    /// keyDown, keyUp, flagsChanged and NX_SYSDEFINED (14: media and brightness keys).
    nonisolated static let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14)

    private(set) var remaining = 0
    var isActive: Bool { tap != nil }

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var panel: NSPanel?
    /// Real end time, so sleep or a stalled main thread can't stretch the 45 s.
    @ObservationIgnored private var endDate = Date.distantPast

    func start() {
        guard tap == nil else { return }
        guard AccessibilityAccess.isTrusted(promptOnce: "keyboardCleanAskedAccessibility") else {
            explainAccessibility()
            return
        }
        // Let the key that started this (↩ in the palette) come back up first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.begin() }
    }

    private func begin() {
        guard tap == nil,
              let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: Self.eventMask, callback: keyboardCleanerCallback, userInfo: nil)
        else { NSLog("VibeCheck: keyboard cleaning couldn't start (event tap refused)"); return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        keyboardCleanerTap = tap
        self.tap = tap
        self.source = source
        remaining = Self.duration
        endDate = Date().addingTimeInterval(TimeInterval(Self.duration))
        showOverlay()
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { KeyboardCleaner.shared.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        remaining = max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
        if remaining == 0 { stop() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        keyboardCleanerTap = nil
        tap = nil
        source = nil
        remaining = 0
        panel?.orderOut(nil)
        panel = nil
    }

    private func showOverlay() {
        let size = NSSize(width: 340, height: 200)
        let screen = NSScreen.main?.frame ?? .zero
        let panel = OverlayPanel(contentRect: NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                                                     width: size.width, height: size.height),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: KeyboardCleanerOverlay(cleaner: self))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func explainAccessibility() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Keyboard cleaning needs Accessibility")
        alert.informativeText = String(localized: "Allow VibeCheck in System Settings → Privacy & Security → Accessibility, then try again. VibeCheck only ignores keys while cleaning mode is on.")
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}

/// The running tap, for re-enabling it from the callback when macOS switches it off after a timeout.
nonisolated(unsafe) private var keyboardCleanerTap: CFMachPort?

/// Swallows every event it's given; re-enables the tap if macOS disabled it (slow callback / user input).
private func keyboardCleanerCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                     userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = keyboardCleanerTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    return nil
}

/// Borderless panels can't become key by default; the Done button needs clicks to land.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct KeyboardCleanerOverlay: View {
    let cleaner: KeyboardCleaner

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Keys are off for \(cleaner.remaining) s")
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            Text("Wipe away. Touch ID and the power button still work.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { cleaner.stop() }
                .controlSize(.large)
        }
        .padding(24)
        .frame(width: 340, height: 200)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(Deck.reduceMotion ? nil : .default, value: cleaner.remaining)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard cleaning")
    }
}
