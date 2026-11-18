import AppKit
import Observation
import SwiftUI

/// Hosting view that lets clicks fall through to the status bar button underneath.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// One status bar item: either a single module or the combined item holding all enabled modules.
/// Clicking it opens the shared deck (home for the combined item, the module's detail otherwise).
@MainActor
final class StatusItemController: NSObject {
    enum Kind: Equatable {
        case single(Module)
        case combined
        case vibe
    }

    let kind: Kind
    private let item: NSStatusItem
    /// The label with its environment, kept so the item can measure it after settings change.
    private var labelView = AnyView(EmptyView())
    private let onClick: (StatusItemController) -> Void

    var button: NSStatusBarButton? { item.button }

    /// Where this item's deck opens.
    var route: DeckRoute {
        if case .single(let module) = kind { return .module(module) }
        return .home
    }

    init(kind: Kind, stats: SystemStats, settings: AppSettings, onClick: @escaping (StatusItemController) -> Void) {
        self.kind = kind
        self.onClick = onClick
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let label: AnyView
        switch kind {
        case .single(let module):
            item.autosaveName = "vibecheck.\(module.rawValue)"
            label = AnyView(MenuBarLabel(module: module))
        case .combined:
            item.autosaveName = "vibecheck.combined"
            label = AnyView(CombinedLabel())
        case .vibe:
            item.autosaveName = "vibecheck.vibe"
            label = AnyView(VibeItemLabel())
        }
        labelView = AnyView(label.environment(stats).environment(settings))
        refreshLength()

        if let button = item.button {
            let host = PassthroughHostingView(rootView: labelView)
            host.sizingOptions = []
            host.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                host.topAnchor.constraint(equalTo: button.topAnchor),
                host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.setAccessibilityLabel(kind == .combined ? "VibeCheck" : "VibeCheck \(title)")
        }
    }

    private var title: String {
        switch kind {
        case .single(let module): module.title
        case .vibe: "Vibe"
        case .combined: "VibeCheck"
        }
    }

    /// Sizes the item to its label's natural width. Values use fixed-width slots, so this stays stable.
    func refreshLength() {
        let width = NSHostingView(rootView: labelView).fittingSize.width
        item.length = max(ceil(width), 8)
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) { onClick(self) }

    func remove() { NSStatusBar.system.removeStatusItem(item) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let stats = SystemStats()
    private let settings = AppSettings.shared
    private let alerts = AlertEngine()
    private lazy var deck = DeckController(stats: stats, settings: settings)
    private var items: [Module: StatusItemController] = [:]
    private var combinedItem: StatusItemController?
    /// The standalone ring shown with separate items.
    private var vibeItem: StatusItemController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        stats.onTick = { [weak self] in
            guard let self else { return }
            self.alerts.evaluate(self.settings.alertRules, stats: self.stats)
        }
        stats.start(interval: settings.refreshInterval)
        syncItems()
        HotkeyManager.shared.onTrigger = { [weak self] module in self?.openFromShortcut(module) }
        configureHotkeys()
        WeatherStore.shared.refresh()

        NotificationCenter.default.addObserver(forName: .vibeCheckSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.syncItems()
                self.configureHotkeys()
                self.stats.start(interval: self.settings.refreshInterval)
            }
        }
        if CommandLine.arguments.contains("--deck-demo") { runDeckDemo() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stats.history.save()
    }

    /// Re-opening the app (e.g. double-clicking it in Finder) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func makeItem(_ kind: StatusItemController.Kind) -> StatusItemController {
        StatusItemController(kind: kind, stats: stats, settings: settings) { [weak self] item in
            guard let self, let button = item.button else { return }
            self.deck.toggle(from: button, route: item.route)
        }
    }

    private func syncItems() {
        deck.close()
        if settings.menuBarStyle == .combined {
            items.values.forEach { $0.remove() }
            items.removeAll()
            vibeItem?.remove()
            vibeItem = nil
            if let combinedItem {
                combinedItem.refreshLength()
            } else {
                combinedItem = makeItem(.combined)
            }
            return
        }

        combinedItem?.remove()
        combinedItem = nil
        // Insert in reverse so the left-to-right order matches Module.allCases.
        for module in settings.moduleOrder.reversed() {
            let enabled = settings.isEnabled(module)
            if enabled, items[module] == nil {
                items[module] = makeItem(.single(module))
            } else if !enabled, let existing = items.removeValue(forKey: module) {
                existing.remove()
            }
            items[module]?.refreshLength() // label style or clock format may have changed
        }
        // Created after the modules so it sits to their left.
        if settings.showVibeRing, vibeItem == nil {
            vibeItem = makeItem(.vibe)
        } else if !settings.showVibeRing {
            vibeItem?.remove()
            vibeItem = nil
        }
        vibeItem?.refreshLength()
    }

    private func configureHotkeys() {
        if settings.hotkeysEnabled {
            HotkeyManager.shared.register(modifier: settings.hotkeyModifier)
        } else {
            HotkeyManager.shared.unregisterAll()
        }
    }

    /// Global shortcut: open the deck on that module, or close it if that module is already showing.
    private func openFromShortcut(_ module: Module) {
        guard settings.isEnabled(module) else { NSSound.beep(); return }
        if deck.isVisible, deck.route == .module(module) { deck.close(); return }
        guard let button = (combinedItem ?? items[module])?.button else { return }
        deck.open(from: button, route: .module(module))
    }

    func showSettings() {
        deck.close()
        if settingsWindow == nil {
            let view = SettingsView(onTestNotification: { [weak self] in self?.alerts.sendTest() })
                .environment(settings).environment(stats)
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: controller)
            window.title = "VibeCheck Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 760, height: 560))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// `--deck-demo`: opens the deck, unfolds CPU, folds back, and logs the window frame at each step.
    private func runDeckDemo() {
        func log(_ step: String) {
            let window = NSApp.windows.first { $0 is DeckPanel }
            NSLog("%@", "VibeCheck deck-demo \(step): visible=\(window?.isVisible ?? false) frame=\(NSStringFromRect(window?.frame ?? .zero)) route=\(deck.route)")
        }
        let steps: [(Double, String, () -> Void)] = [
            (1.0, "launch", {
                for item in [self.combinedItem, self.vibeItem].compactMap({ $0 }) + Array(self.items.values) {
                    guard let button = item.button, let window = button.window else { continue }
                    let inScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
                    NSLog("%@", "VibeCheck deck-demo item \(item.kind): window=\(NSStringFromRect(window.frame)) buttonOnScreen=\(NSStringFromRect(inScreen)) screen=\(NSStringFromRect(window.screen?.frame ?? .zero)) visible=\(NSStringFromRect(window.screen?.visibleFrame ?? .zero))")
                }
                for screen in NSScreen.screens {
                    NSLog("%@", "VibeCheck deck-demo screen: frame=\(NSStringFromRect(screen.frame)) visible=\(NSStringFromRect(screen.visibleFrame))")
                }
                guard let button = (self.combinedItem ?? self.items[.network] ?? self.items.values.first)?.button else { return }
                self.deck.ignoresOutsideClicks = true
                self.deck.open(from: button, route: .home)
            }),
            (1.6, "home", { self.deck.model.go(.module(.cpu)) }),
            (2.4, "cpu", { self.deck.model.go(.home) }),
            (3.2, "home-again", { self.deck.close() }),
            (3.8, "closed", { self.deck.ignoresOutsideClicks = false; self.showSettings() }),
            (4.8, "settings", {
                let window = NSApp.windows.first { $0.title == "VibeCheck Settings" }
                NSLog("%@", "VibeCheck deck-demo settings-window: visible=\(window?.isVisible ?? false) frame=\(NSStringFromRect(window?.frame ?? .zero)) vibe=\(self.stats.vibe.vibe.title) verdict=\(self.stats.vibe.verdict)")
                window?.close()
            }),
        ]
        for (time, name, action) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) { log(name); action() }
        }
    }
}
