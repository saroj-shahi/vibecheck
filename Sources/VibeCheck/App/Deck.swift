import AppKit
import Observation
import QuartzCore
import SwiftUI

enum DeckRoute: Equatable {
    case home
    case module(Module)
}

enum DeckDirection { case left, right, up, down }

/// Shared motion and layout constants for the deck.
enum Deck {
    static let width: CGFloat = 360
    static let cornerRadius: CGFloat = 18
    static let columns = 3
    /// Unfold / fold spring (response 0.38, damping 0.86).
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.86)
    /// Window resize curve matched to the spring so frame and content land together.
    static let resizeDuration: TimeInterval = 0.38
    @MainActor static let resizeCurve = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.1, 1.0)

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var animation: Animation { reduceMotion ? .easeInOut(duration: 0.15) : spring }
}

/// What the deck is showing and which tile has keyboard focus.
@Observable
@MainActor
final class DeckModel {
    private(set) var route: DeckRoute = .home
    /// Tiles on the home grid, in menu bar order.
    var modules: [Module] = []
    var focusIndex: Int?
    /// Focus rings only appear once the keyboard is used, like the rest of macOS.
    var keyboardFocusVisible = false
    /// Grid position of the tile that opened the current detail view; staggers the fold/unfold.
    private(set) var originIndex: Int?

    @ObservationIgnored var onRouteChange: ((DeckRoute) -> Void)?
    /// Closes the deck window (set by the controller).
    @ObservationIgnored var requestClose: (() -> Void)?

    /// ⌘K palette: nil when closed, else what has been typed.
    private(set) var paletteQuery: String?
    /// Selected row among the filtered results.
    var paletteIndex = 0 { didSet { if paletteIndex != oldValue { paletteConfirmID = nil } } }
    /// A command that asked for a second ↩ (Quit); cleared by any other key or selection change.
    var paletteConfirmID: String?
    var paletteOpen: Bool { paletteQuery != nil }

    func openPalette(_ query: String = "") {
        withAnimation(Deck.reduceMotion ? nil : .easeOut(duration: 0.15)) { paletteQuery = query }
        paletteIndex = 0
        paletteConfirmID = nil
    }

    func closePalette() {
        guard paletteQuery != nil else { return }
        withAnimation(Deck.reduceMotion ? nil : .easeOut(duration: 0.12)) { paletteQuery = nil }
        paletteIndex = 0
        paletteConfirmID = nil
    }

    func typeInPalette(_ text: String) {
        paletteQuery = (paletteQuery ?? "") + text
        paletteIndex = 0
        paletteConfirmID = nil
    }

    func deleteInPalette() {
        guard var query = paletteQuery, !query.isEmpty else { return }
        query.removeLast()
        paletteQuery = query
        paletteIndex = 0
        paletteConfirmID = nil
    }

    func go(_ route: DeckRoute, animated: Bool = true) {
        closePalette()   // e.g. ⌘2 while the palette is open
        guard route != self.route else { return }
        if case .module(let module) = route { originIndex = modules.firstIndex(of: module) }
        if animated {
            withAnimation(Deck.animation) { self.route = route }
        } else {
            self.route = route
        }
        if case .module(let module) = route, let index = modules.firstIndex(of: module) { focusIndex = index }
        onRouteChange?(route)
    }

    /// Delay for a home tile's fold/unfold: tiles farther from the origin move later (25 ms per step).
    func staggerDelay(for index: Int) -> Double {
        guard let origin = originIndex, !Deck.reduceMotion else { return 0 }
        let (r0, c0) = (origin / Deck.columns, origin % Deck.columns)
        let (r1, c1) = (index / Deck.columns, index % Deck.columns)
        return Double(abs(r0 - r1) + abs(c0 - c1)) * 0.025
    }

    /// Arrow-key movement on a grid; stays put at edges instead of wrapping.
    nonisolated static func move(_ index: Int?, _ direction: DeckDirection, count: Int, columns: Int = Deck.columns) -> Int? {
        guard count > 0 else { return nil }
        guard let index else { return 0 }
        switch direction {
        case .left: return max(0, index - 1)
        case .right: return min(count - 1, index + 1)
        case .up: return index - columns >= 0 ? index - columns : index
        case .down: return index + columns < count ? index + columns : index
        }
    }
}

/// Borderless, non-activating panel that hangs under the menu bar (replaces NSPopover).
final class DeckPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Deck.width, height: 300),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the single deck window: positioning under a status item, resizing to content, dismissal,
/// keyboard handling, and starting/stopping the expensive samplers for whatever is on screen.
@MainActor
final class DeckController: NSObject {
    let model = DeckModel()
    private let panel = DeckPanel()
    private unowned let stats: SystemStats
    private unowned let settings: AppSettings
    private weak var anchor: NSStatusBarButton?
    private var contentHeight: CGFloat = 300
    private var monitors: [Any] = []
    private var holdsProcessDemand = false
    private var holdsNetworkDemand = false
    private var holdsSensorDemand = false
    /// Bumped on every open/close so a stale close-fade can't hide a deck that was just reopened.
    private var generation = 0
    /// Set by `--deck-demo` so stray clicks elsewhere don't dismiss the deck mid-demo.
    var ignoresOutsideClicks = false

    var isVisible: Bool { panel.isVisible }
    var route: DeckRoute { model.route }

    init(stats: SystemStats, settings: AppSettings) {
        self.stats = stats
        self.settings = settings
        super.init()

        let root = DeckRoot(onHeight: { [weak self] height in self?.contentHeightChanged(height) })
            .environment(stats).environment(settings).environment(model)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []   // the controller sizes the window; SwiftUI must not resize it

        // A plain frame-based container between the material and SwiftUI, so nothing in the view tree
        // can derive the window size from content (that collapsed the window to 10 × 10 pt).
        let initial = NSRect(x: 0, y: 0, width: Deck.width, height: 300)
        let container = NSView(frame: initial)
        container.autoresizingMask = [.width, .height]
        host.frame = initial
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        let background: NSView
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: initial)
            glass.cornerRadius = Deck.cornerRadius
            glass.contentView = container
            background = glass
        } else {
            let effect = NSVisualEffectView(frame: initial)
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = Deck.cornerRadius
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            effect.addSubview(container)
            background = effect
        }
        background.autoresizingMask = [.width, .height]
        panel.contentView = background
        panel.setContentSize(initial.size)

        model.onRouteChange = { [weak self] _ in self?.updateSamplerDemand() }
        model.requestClose = { [weak self] in self?.close() }
    }

    // MARK: Showing and hiding

    /// Status item click: open on `route`, switch to it, or close if it's already showing there.
    func toggle(from button: NSStatusBarButton, route: DeckRoute) {
        if isVisible, anchor === button, model.route == route || route == .home {
            close()
        } else {
            open(from: button, route: route)
        }
    }

    func open(from button: NSStatusBarButton, route: DeckRoute) {
        model.modules = settings.orderedModules
        let wasVisible = isVisible
        let anchorChanged = anchor !== button
        anchor = button

        if wasVisible {
            model.go(route)
            if anchorChanged { reposition(animated: true) }
            return
        }

        generation += 1
        model.go(route, animated: false)
        model.keyboardFocusVisible = false
        model.focusIndex = nil
        // Lay out once so the content height is known before the window appears.
        panel.contentView?.layoutSubtreeIfNeeded()
        let final = targetFrame()
        NSApp.activate()

        // Order front first (invisible), then set the frame: showing a window can re-derive its size,
        // so the frame must be applied after it is on screen.
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        if Deck.reduceMotion {
            panel.setFrame(final, display: true)
            panel.alphaValue = 1
        } else {
            // Drop in from 6 pt above with a quick fade (≈ spring response 0.28, damping 0.9).
            panel.setFrame(final.offsetBy(dx: 0, dy: 6), display: true)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = Deck.resizeCurve
                panel.animator().setFrame(final, display: true)
                panel.animator().alphaValue = 1
            }
        }
        installMonitors()
        updateSamplerDemand()
    }

    func close() {
        guard isVisible else { return }
        removeMonitors()
        model.closePalette()
        generation += 1
        let closing = generation
        let panel = self.panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Deck.reduceMotion ? 0 : 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                guard self.generation == closing else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
                self.updateSamplerDemand()
            }
        })
    }

    // MARK: Geometry

    private func contentHeightChanged(_ height: CGFloat) {
        guard abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        if isVisible { reposition(animated: true) }
    }

    /// Hangs the deck 6 pt under the clicked status item, centred on it and kept on its display.
    /// Uses the button's on-screen rect (status item windows can be taller than the menu bar and poke
    /// above the screen, so their window frame isn't a reliable anchor). If the item isn't placed in a
    /// menu bar yet (right after launch), falls back to the top-right of the main display.
    private func targetFrame() -> NSRect {
        let anchorRect = anchorRectOnScreen()
        let screen = anchorRect.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } }
            ?? anchor?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return NSRect(x: 0, y: 0, width: Deck.width, height: contentHeight) }
        let visible = screen.visibleFrame

        let top = visible.maxY - 6
        var centerX = visible.maxX - Deck.width / 2 - 8
        if let rect = anchorRect, Self.isInMenuBar(rect, screen: screen.frame, visible: visible) {
            centerX = rect.midX
        }
        let height = max(160, min(ceil(contentHeight), top - visible.minY - 12))
        let x = min(max(centerX - Deck.width / 2, visible.minX + 8), visible.maxX - Deck.width - 8)
        return NSRect(x: x, y: top - height, width: Deck.width, height: height)
    }

    private func anchorRectOnScreen() -> NSRect? {
        guard let button = anchor, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// True when the rect's centre sits in the strip between the visible area's top and the screen's top
    /// (with a little slack, since the menu bar height varies by display and notch).
    nonisolated static func isInMenuBar(_ rect: NSRect, screen: NSRect, visible: NSRect) -> Bool {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        return center.x >= screen.minX && center.x <= screen.maxX
            && center.y >= visible.maxY - 10 && center.y <= screen.maxY + 20
    }

    private func reposition(animated: Bool) {
        let frame = targetFrame()
        guard animated, !Deck.reduceMotion else {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Deck.resizeDuration
            context.timingFunction = Deck.resizeCurve
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [panel] in
            MainActor.assumeIsolated { panel.invalidateShadow() }
        })
    }

    // MARK: Dismissal and keyboard

    private func installMonitors() {
        removeMonitors()
        if !ignoresOutsideClicks, let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { monitors.append(clicks) }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            // Copy the plain values out so nothing non-Sendable crosses into the main-actor call.
            let key = KeyPress(code: event.keyCode, characters: event.charactersIgnoringModifiers,
                               command: event.modifierFlags.contains(.command), windowNumber: event.windowNumber)
            let handled = MainActor.assumeIsolated { self?.handleKey(key) ?? false }
            return handled ? nil : event
        }) { monitors.append(keys) }
        if !ignoresOutsideClicks {
            NotificationCenter.default.addObserver(self, selector: #selector(appResigned),
                                                   name: NSApplication.didResignActiveNotification, object: nil)
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
    }

    @objc private func appResigned() { close() }

    struct KeyPress: Sendable {
        let code: UInt16
        let characters: String?
        let command: Bool
        let windowNumber: Int
    }

    /// Returns true when the key was handled.
    private func handleKey(_ event: KeyPress) -> Bool {
        guard isVisible, event.windowNumber == panel.windowNumber else { return false }

        if event.command, event.characters == "k" {
            if model.paletteOpen { model.closePalette() } else { model.openPalette() }
            return true
        }
        if model.paletteOpen, let handled = handlePaletteKey(event) { return handled }

        if event.command {
            switch event.characters {
            case ",": close(); (NSApp.delegate as? AppDelegate)?.showSettings(); return true
            case "w": close(); return true
            case let key? where Module.forShortcutKey(key) != nil:
                let module = Module.forShortcutKey(key)!
                if settings.isEnabled(module) { model.go(.module(module)) } else { NSSound.beep() }
                return true
            default: return false
            }
        }

        switch event.code {
        case 53: // Escape: back, then close
            if model.route == .home { close() } else { model.go(.home) }
            return true
        case 36, 76: // Return / Enter
            if model.route == .home, let index = model.focusIndex, model.modules.indices.contains(index) {
                model.go(.module(model.modules[index]))
            }
            return true
        case 123, 124, 125, 126:
            guard model.route == .home else { return false }
            let direction: DeckDirection = [123: .left, 124: .right, 125: .down, 126: .up][event.code]!
            model.keyboardFocusVisible = true
            withAnimation(.easeOut(duration: 0.12)) {
                model.focusIndex = DeckModel.move(model.focusIndex, direction, count: model.modules.count)
            }
            return true
        default:
            // Type-to-act: a letter or digit on the home grid opens the palette already filtered.
            if model.route == .home, let text = Self.typedText(event) {
                model.openPalette(text)
                return true
            }
            return false
        }
    }

    /// Keys while the palette is open; nil lets the normal handling run (⌘-digits, ⌘W, ⌘,).
    private func handlePaletteKey(_ event: KeyPress) -> Bool? {
        if event.command { return nil }
        let results = DeckCommands.filter(DeckCommands.all(model: model, settings: settings),
                                          query: model.paletteQuery ?? "")
        switch event.code {
        case 53: // Escape: clear the query, then close the palette
            if model.paletteQuery?.isEmpty == false { model.openPalette() } else { model.closePalette() }
        case 36, 76:
            if results.indices.contains(model.paletteIndex) { DeckCommands.activate(results[model.paletteIndex], model: model) }
        case 125: model.paletteIndex = min(model.paletteIndex + 1, max(results.count - 1, 0))
        case 126: model.paletteIndex = max(model.paletteIndex - 1, 0)
        case 51: model.deleteInPalette()
        case 123, 124: break
        default:
            if let text = Self.typedText(event, allowSpace: true) { model.typeInPalette(text) }
        }
        return true
    }

    /// Printable text from a key press (letters, digits, punctuation), nil for control keys.
    nonisolated static func typedText(_ event: KeyPress, allowSpace: Bool = false) -> String? {
        guard !event.command, let chars = event.characters, chars.count == 1, let scalar = chars.unicodeScalars.first
        else { return nil }
        if scalar == " " { return allowSpace ? " " : nil }
        let printable = CharacterSet.alphanumerics.union(.punctuationCharacters).union(.symbols)
        guard printable.contains(scalar), scalar.value < 0xF700 else { return nil }   // F700+: arrow/function keys
        return chars
    }

    // MARK: Samplers

    /// `ps` and `nettop` only run while a view that shows their data is on screen.
    private func updateSamplerDemand() {
        let visible = isVisible
        // Home needs processes too: the vibe verdict names the loudest app.
        let wantsProcesses = visible && [.home, .module(.cpu), .module(.memory)].contains(model.route)
        let wantsNetwork = visible && model.route == .module(.network)
        let wantsSensors = visible && model.route == .module(.sensors)
        stats.processInterval = model.route == .home ? 5 : 0
        if wantsSensors != holdsSensorDemand {
            stats.sensorDemand = max(0, stats.sensorDemand + (wantsSensors ? 1 : -1))
            holdsSensorDemand = wantsSensors
        }
        if wantsProcesses != holdsProcessDemand {
            stats.processDemand = max(0, stats.processDemand + (wantsProcesses ? 1 : -1))
            holdsProcessDemand = wantsProcesses
        }
        if wantsNetwork != holdsNetworkDemand {
            stats.networkAppDemand = max(0, stats.networkAppDemand + (wantsNetwork ? 1 : -1))
            holdsNetworkDemand = wantsNetwork
        }
    }
}
