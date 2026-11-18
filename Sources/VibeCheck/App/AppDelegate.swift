import AppKit
import SwiftUI

/// Hosting view that lets clicks fall through to the status bar button underneath.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class ModuleStatusItem: NSObject, NSPopoverDelegate {
    let module: Module
    private let item: NSStatusItem
    private let popover = NSPopover()
    private unowned let stats: SystemStats

    init(module: Module, stats: SystemStats, settings: AppSettings) {
        self.module = module
        self.stats = stats
        item = NSStatusBar.system.statusItem(withLength: module.labelWidth)
        item.autosaveName = "vibecheck.\(module.rawValue)"
        super.init()

        if let button = item.button {
            let label = PassthroughHostingView(rootView: MenuBarLabel(module: module).environment(stats))
            label.sizingOptions = []
            label.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                label.topAnchor.constraint(equalTo: button.topAnchor),
                label.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
            button.target = self
            button.action = #selector(toggle(_:))
            button.setAccessibilityLabel("VibeCheck \(module.title)")
        }

        let controller = NSHostingController(rootView: ModulePanel(module: module)
            .environment(stats).environment(settings))
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    var wantsProcesses: Bool { module == .cpu || module == .memory }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        if popover.isShown { popover.performClose(sender); return }
        if wantsProcesses { stats.processDemand += 1 }
        NSApp.activate()
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
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
    private var items: [Module: ModuleStatusItem] = [:]
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        stats.start(interval: settings.refreshInterval)
        syncItems()
        NotificationCenter.default.addObserver(forName: .vibeCheckSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.syncItems()
                self.stats.start(interval: self.settings.refreshInterval)
            }
        }
    }

    /// Re-opening the app (e.g. double-clicking it in Finder) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func syncItems() {
        // Insert in reverse so the left-to-right order matches Module.allCases.
        for module in Module.allCases.reversed() {
            let enabled = settings.isEnabled(module)
            if enabled, items[module] == nil {
                items[module] = ModuleStatusItem(module: module, stats: stats, settings: settings)
            } else if !enabled, let existing = items.removeValue(forKey: module) {
                existing.remove()
            }
        }
    }

    func showSettings() {
        items.values.forEach { $0.close() }
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView().environment(settings))
            controller.sizingOptions = .preferredContentSize
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
