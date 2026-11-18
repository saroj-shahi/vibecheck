import AppKit
import Observation
import SwiftUI

/// Hosting view that lets clicks fall through to the status bar button underneath.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Which tab the combined panel is showing (shortcuts switch it).
@Observable
@MainActor
final class CombinedSelection {
    var module: Module = .cpu
}

/// One status bar item: either a single module or the combined item holding all enabled modules.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    enum Kind: Equatable {
        case single(Module)
        case combined
    }

    let kind: Kind
    private let item: NSStatusItem
    private let popover = NSPopover()
    private unowned let stats: SystemStats
    private unowned let settings: AppSettings
    private unowned let selection: CombinedSelection
    /// The label with its environment, kept so the item can measure it after settings change.
    private var labelView = AnyView(EmptyView())

    init(kind: Kind, stats: SystemStats, settings: AppSettings, selection: CombinedSelection) {
        self.kind = kind
        self.stats = stats
        self.settings = settings
        self.selection = selection
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let label: AnyView
        let content: AnyView
        switch kind {
        case .single(let module):
            item.autosaveName = "vibecheck.\(module.rawValue)"
            label = AnyView(MenuBarLabel(module: module))
            content = AnyView(ModulePanel(module: module))
        case .combined:
            item.autosaveName = "vibecheck.combined"
            label = AnyView(CombinedLabel())
            content = AnyView(CombinedPanel())
        }
        labelView = AnyView(label.environment(stats).environment(settings).environment(selection))
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

        let controller = NSHostingController(rootView: content
            .environment(stats).environment(settings).environment(selection))
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    private var title: String {
        if case .single(let module) = kind { return module.title }
        return "VibeCheck"
    }

    /// Sizes the item to its label's natural width. Values use fixed-width slots, so this stays stable.
    func refreshLength() {
        let width = NSHostingView(rootView: labelView).fittingSize.width
        item.length = max(ceil(width), 8)
    }

    private var wantsProcesses: Bool {
        switch kind {
        case .single(let module): module == .cpu || module == .memory
        case .combined: true
        }
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        popover.isShown ? close() : open()
    }

    /// Shortcut behaviour: open (on the right tab), or close if that panel is already showing.
    func handleShortcut(for module: Module) {
        if kind == .combined {
            if popover.isShown, selection.module == module { close(); return }
            selection.module = module
            if !popover.isShown { open() }
        } else {
            popover.isShown ? close() : open()
        }
    }

    private func open() {
        guard let button = item.button else { return }
        if wantsProcesses { stats.processDemand += 1 }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() { if popover.isShown { popover.performClose(nil) } }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            if wantsProcesses { stats.processDemand = max(0, stats.processDemand - 1) }
        }
    }

    func remove() {
        close()
        NSStatusBar.system.removeStatusItem(item)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let stats = SystemStats()
    private let settings = AppSettings.shared
    private let selection = CombinedSelection()
    private let alerts = AlertEngine()
    private var items: [Module: StatusItemController] = [:]
    private var combinedItem: StatusItemController?
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

        NotificationCenter.default.addObserver(forName: .vibeCheckSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.syncItems()
                self.configureHotkeys()
                self.stats.start(interval: self.settings.refreshInterval)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stats.history.save()
    }

    /// Re-opening the app (e.g. double-clicking it in Finder) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func syncItems() {
        if settings.menuBarStyle == .combined {
            items.values.forEach { $0.remove() }
            items.removeAll()
            if let combinedItem {
                combinedItem.refreshLength()
            } else {
                combinedItem = StatusItemController(kind: .combined, stats: stats, settings: settings, selection: selection)
            }
            return
        }

        combinedItem?.remove()
        combinedItem = nil
        // Insert in reverse so the left-to-right order matches Module.allCases.
        for module in Module.allCases.reversed() {
            let enabled = settings.isEnabled(module)
            if enabled, items[module] == nil {
                items[module] = StatusItemController(kind: .single(module), stats: stats,
                                                     settings: settings, selection: selection)
            } else if !enabled, let existing = items.removeValue(forKey: module) {
                existing.remove()
            }
            items[module]?.refreshLength() // label style or clock format may have changed
        }
    }

    private func configureHotkeys() {
        if settings.hotkeysEnabled {
            HotkeyManager.shared.register(modifier: settings.hotkeyModifier)
        } else {
            HotkeyManager.shared.unregisterAll()
        }
    }

    private func openFromShortcut(_ module: Module) {
        guard settings.isEnabled(module) else { NSSound.beep(); return }
        if let combinedItem {
            combinedItem.handleShortcut(for: module)
        } else if let item = items[module] {
            items.values.filter { $0 !== item }.forEach { $0.close() }
            item.handleShortcut(for: module)
        }
    }

    func showSettings() {
        items.values.forEach { $0.close() }
        combinedItem?.close()
        if settingsWindow == nil {
            let view = SettingsView(onTestNotification: { [weak self] in self?.alerts.sendTest() })
                .environment(settings)
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "VibeCheck Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
