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
        /// Standalone keep-awake cup: click toggles with the default length, right-click shows a menu.
        case keepAwake
    }

    let kind: Kind
    private let item: NSStatusItem
    /// The label with its environment, kept so the item can measure it after settings change.
    private var labelView = AnyView(EmptyView())
    private let onClick: (StatusItemController) -> Void
    private unowned let stats: SystemStats
    private unowned let settings: AppSettings
    /// Combined item only: how many stats fit beside the camera notch.
    let fit = CombinedFit()
    /// Ring item only: lights up while a drag hovers over it.
    let dropState = RingDropState()
    /// Ring item only: called with what was dropped on it.
    var onDrop: (([URL]) -> Void)?

    var button: NSStatusBarButton? { item.button }

    /// Where this item's deck opens.
    var route: DeckRoute {
        if case .single(let module) = kind { return .module(module) }
        return .home
    }

    init(kind: Kind, stats: SystemStats, settings: AppSettings, onClick: @escaping (StatusItemController) -> Void) {
        self.kind = kind
        self.onClick = onClick
        self.stats = stats
        self.settings = settings
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let label: AnyView
        switch kind {
        case .single(let module):
            item.autosaveName = AppSettings.autosaveName(module.rawValue, generation: settings.statusItemGeneration)
            label = AnyView(MenuBarLabel(module: module))
        case .combined:
            item.autosaveName = "vibecheck.combined"
            label = AnyView(CombinedLabel())
        case .vibe:
            item.autosaveName = AppSettings.autosaveName("vibe", generation: settings.statusItemGeneration)
            label = AnyView(VibeItemLabel())
        case .keepAwake:
            item.autosaveName = AppSettings.autosaveName("keepawake", generation: settings.statusItemGeneration)
            label = AnyView(KeepAwakeItemLabel())
        }
        labelView = AnyView(label.environment(stats).environment(settings).environment(fit).environment(dropState))
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
            if kind == .vibe {
                let target = RingDropView(state: dropState) { [weak self] urls in self?.onDrop?(urls) }
                target.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(target)
                NSLayoutConstraint.activate([
                    target.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                    target.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                    target.topAnchor.constraint(equalTo: button.topAnchor),
                    target.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                ])
            }
            button.target = self
            button.action = #selector(buttonClicked(_:))
            if kind == .keepAwake { button.sendAction(on: [.leftMouseUp, .rightMouseUp]) }
            button.setAccessibilityLabel(kind == .combined ? String(localized: "VibeCheck") : String(localized: "VibeCheck \(title)"))
        }
        if kind == .combined { observePlacement() }
        updateVerdict()
    }

    // MARK: Verdict tooltip

    /// The verdict last shown, so the tooltip and label are only touched when it changes.
    private var shownVerdict: String?

    /// Hover tooltip and VoiceOver label for the items that stand for the whole Mac (ring and combined):
    /// the verdict sentence, so the answer is there without opening the deck. Other items keep their title.
    static func verdictText(for kind: Kind, verdict: String, keepAwake: Bool = false) -> (toolTip: String, accessibility: String)? {
        let awake = String(localized: "Keeping your Mac awake.")
        let suffix = keepAwake ? " \(awake)" : ""
        switch kind {
        case .combined: return ("\(verdict)\(suffix)", String(localized: "VibeCheck. \(verdict)\(suffix)"))
        case .vibe: return ("\(verdict)\(suffix)", String(localized: "VibeCheck vibe. \(verdict)\(suffix)"))
        case .single, .keepAwake: return nil
        }
    }

    func updateVerdict() {
        let verdict = stats.vibe.verdict
        let awake = AwakeCup.inRing(settings)
        let key = awake ? "\(verdict)|awake" : verdict
        guard key != shownVerdict, let button = item.button,
              let text = Self.verdictText(for: kind, verdict: verdict, keepAwake: awake) else { return }
        shownVerdict = key
        button.toolTip = text.toolTip
        button.setAccessibilityLabel(text.accessibility)
    }

    /// Ring item only: the shape of the badge last measured. The item's length isn't re-measured by itself, so
    /// it's resized here when the badge appears, goes away or changes shape ("CPU 99%" → "CPU 100%"); digits
    /// are monospaced, so a new value with as many digits keeps the width and the neighbours stay put.
    private var measuredBadge: String?

    static func badgeShape(_ badge: String?) -> String? {
        badge.map { String($0.map { $0.isNumber ? "0" : $0 }) }
    }

    func updateBadgeWidth() {
        guard kind == .vibe else { return }
        let badge = VibeItemLabel.shownBadge(stats.vibe, ringShown: settings.ringVisible, isShown: settings.showsInMenuBar)
        let shape = Self.badgeShape(badge)
        guard shape != measuredBadge else { return }
        measuredBadge = shape
        refreshLength()
    }

    // MARK: Notch auto-fit (combined item)

    private func observePlacement() {
        let center = NotificationCenter.default
        let refit: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refitAroundNotch() }
        }
        if let window = item.button?.window {
            center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main, using: refit)
            center.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main, using: refit)
        }
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: refit)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main, using: refit)
        // The item gets its final position shortly after launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refitAroundNotch() }
    }

    /// Shows only as many stats as fit between the camera notch and the item's right edge (which stays put
    /// as the item resizes). On displays without a notch, or with the setting off, everything is shown.
    func refitAroundNotch() {
        guard kind == .combined else { return }
        var limit: Int?
        if settings.autoFitNotch, let button = item.button, let window = button.window, let screen = window.screen {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            if let available = NotchFit.availableWidth(itemRect: rect, notchRight: screen.auxiliaryTopRightArea,
                                                       notchLeft: screen.auxiliaryTopLeftArea) {
                let spacing = settings.menuBarSpacing
                let widths = settings.orderedModules.map { module in
                    NSHostingView(rootView: MenuBarLabel(module: module, padded: false)
                        .environment(stats).environment(settings)).fittingSize.width
                }
                let chip = NSHostingView(rootView: HiddenCountChip(count: 8)).fittingSize.width
                let ring: CGFloat = settings.ringVisible ? 16 : 0
                let cup = AwakeCup.isShown(settings) ? NSHostingView(rootView: AwakeCup()).fittingSize.width + spacing.between : 0
                let fitted = NotchFit.visibleCount(itemWidths: widths, fixed: ring + cup + spacing.padding * 2,
                                                   gap: spacing.between, chipWidth: chip, available: available)
                limit = NotchFit.capped(fitted: fitted, total: widths.count, cap: settings.notchMaxStats)
            }
        }
        guard limit != fit.visibleCount else { return }
        fit.visibleCount = limit
        refreshLength()
    }

    /// True when macOS has hidden this item behind the notch (or off the screen's left edge).
    var isHiddenByNotch: Bool {
        guard let window = item.button?.window, window.isVisible,
              let screen = window.screen ?? NSScreen.main else { return false }
        // Off the left edge also happens when macOS parks an item; only count it when it really isn't drawn.
        if window.frame.minX < screen.frame.minX - 1, window.occlusionState.contains(.visible) { return false }
        return NotchFit.isHidden(itemRect: window.frame, screenFrame: screen.frame,
                                 notchLeft: screen.auxiliaryTopLeftArea, notchRight: screen.auxiliaryTopRightArea)
    }

    private var title: String {
        switch kind {
        case .single(let module): module.title
        case .vibe: String(localized: "Vibe")
        case .combined: String(localized: "VibeCheck")
        case .keepAwake: String(localized: "Keep Awake")
        }
    }

    /// Sizes the item to its label's natural width. Values use fixed-width slots, so this stays stable.
    func refreshLength() {
        let width = NSHostingView(rootView: labelView).fittingSize.width
        item.length = max(ceil(width), 8)
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) { onClick(self) }

    /// Shows `menu` from this item as if it were the item's own menu (the standard status item pattern).
    func show(_ menu: NSMenu) {
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    func remove() { NSStatusBar.system.removeStatusItem(item) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let stats = SystemStats()
    let launchedAt = Date()
    private let settings = AppSettings.shared
    private let alerts = AlertEngine()
    private lazy var deck = DeckController(stats: stats, settings: settings)
    private var items: [Module: StatusItemController] = [:]
    private var combinedItem: StatusItemController?
    /// The standalone ring shown with separate items.
    private var vibeItem: StatusItemController?
    private var settingsWindow: NSWindow?
    /// The standalone Keep Awake item, when it's switched on in Settings.
    private var keepAwakeItem: StatusItemController?
    private let keepAwakeMenu = KeepAwakeMenu()
    /// Generation the separate items were created with; a reorder in Settings bumps it.
    private var itemGeneration = 0
    private var agentWatch = AgentWatch()

    func applicationDidFinishLaunching(_ notification: Notification) {
        alerts.log = NotificationLog.shared
        stats.onTick = { [weak self] in
            guard let self else { return }
            CallGuard.shared.tick(stats: self.stats, alerts: self.alerts)
            self.alerts.evaluate(self.settings.alertRules, stats: self.stats)
            KeepAwake.shared.check()
            self.vibeItem?.updateVerdict()
            self.vibeItem?.updateBadgeWidth()
            self.checkNotchHiding()
            self.watchAgents()
            self.combinedItem?.updateVerdict()
        }
        KeepAwake.shared.batteryProvider = { [unowned stats] in stats.battery }
        KeepAwake.shared.onSessionEnded = { [weak self] reason in
            guard let self else { return }
            // A finished focus session always says so; other endings follow the keep-awake setting.
            if reason == .focusDone {
                self.alerts.notify(title: String(localized: "Focus session done"), body: String(localized: "Take a break. Your Mac can sleep again."), kind: .keepAwake)
                return
            }
            guard reason.notifies, self.settings.keepAwakeNotify else { return }
            self.alerts.notify(title: String(localized: "Keep awake ended"), body: String(localized: "\(reason.message) Your Mac can sleep again."), kind: .keepAwake)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { KeepAwake.shared.check() }
        }
        HotkeyManager.shared.onKeepAwake = { KeepAwake.shared.toggle() }
        if settings.keepAwakeAtLaunch { KeepAwake.shared.start(minutes: settings.keepAwakeDefaultMinutes) }
        KeepAwake.shared.check() // triggers (plugged in, external display) apply right away
        stats.start(interval: settings.refreshInterval)
        itemGeneration = settings.statusItemGeneration
        syncItems()
        HotkeyManager.shared.onTrigger = { [weak self] module in self?.openFromShortcut(module) }
        configureHotkeys()
        WeatherStore.shared.refresh()
        AgentUsageStore.shared.start()
        BluetoothSnooze.shared.isEnabled = { [unowned settings] in settings.bluetoothOffWhileAsleep }
        BluetoothSnooze.shared.start()

        NotificationCenter.default.addObserver(forName: .vibeCheckSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.noteExplicitStyleChoice()
                self.syncItems()
                self.configureHotkeys()
                self.stats.start(interval: self.settings.refreshInterval)
            }
        }
        // The cup appears or disappears: resize items without closing the deck.
        NotificationCenter.default.addObserver(forName: .vibeCheckKeepAwakeChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.combinedItem?.refitAroundNotch()
                self.combinedItem?.refreshLength()
                self.syncVibeItem()
                self.vibeItem?.updateVerdict()
                self.combinedItem?.updateVerdict()
                self.keepAwakeItem?.refreshLength()
            }
        }
        if CommandLine.arguments.contains("--deck-demo") { runDeckDemo() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        KeepAwake.shared.stop()
        stats.history.save()
        stats.vibeReplay.save()
        stats.batteryLog.save()
    }

    /// Re-opening the app (e.g. double-clicking it in Finder) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    /// Opt-in "agent is done" notification after a long run. Runs are tracked even while it's off; a run's
    /// length counts from the first write VibeCheck saw (launch, or the first scan that picked it up).
    private func watchAgents() {
        let finished = agentWatch.update(AgentUsageStore.shared.sample.agents, now: Date())
        guard settings.notifyAgentFinished else { return }
        for run in finished {
            let message = AgentWatch.message(run)
            alerts.notify(title: message.title, body: message.body, kind: .agent)
        }
    }

    private func makeItem(_ kind: StatusItemController.Kind) -> StatusItemController {
        let item = StatusItemController(kind: kind, stats: stats, settings: settings) { [weak self] item in
            guard let self, let button = item.button else { return }
            // ⌥-click on the ring does what the cup's click does.
            if item.kind == .vibe, NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                self.deck.close()
                KeepAwake.shared.toggle()
                return
            }
            self.deck.toggle(from: button, route: item.route)
        }
        if kind == .vibe { item.onDrop = { [weak self] urls in self?.handleDrop(urls) } }
        return item
    }

    /// A file, folder or app dropped on the ring: keep awake until it stops changing, or while the app runs.
    private func handleDrop(_ urls: [URL]) {
        guard let url = urls.first else { return }
        deck.close()
        switch RingDropAction.action(for: url) {
        case .keepAwake(let end):
            KeepAwake.shared.start(end)
            KeepAwake.shared.check()
        }
    }

    // MARK: Notch auto-collapse

    private var notchWatch = NotchHideWatch()

    /// Separate items: when macOS hides one behind the notch for a few seconds, switch to the combined item
    /// (which fits itself around the notch) and say so once. Turning separate items back on is respected.
    private func checkNotchHiding() {
        guard NotchHideWatch.mayCollapse(separate: settings.menuBarStyle == .separate, autoFit: settings.autoFitNotch,
                                         optedOut: settings.notchCollapseOptOut) else {
            notchWatch.hiddenSince = nil
            return
        }
        let separate = Array(items.values) + [vibeItem, keepAwakeItem].compactMap { $0 }
        let hidden = separate.contains { $0.isHiddenByNotch }
        guard notchWatch.update(hidden: hidden, now: Date()) else { return }
        notchWatch.hiddenSince = nil
        settings.notchAutoCollapsed = true
        settings.menuBarStyle = .combined
        if !settings.notchNoticeShown {
            settings.notchNoticeShown = true
            alerts.notify(title: NotchHideWatch.noticeTitle, body: NotchHideWatch.noticeBody, kind: .alert)
        }
    }

    /// The owner switched back to separate items after an automatic collapse: don't collapse again.
    private func noteExplicitStyleChoice() {
        guard settings.notchAutoCollapsed, settings.menuBarStyle == .separate else { return }
        settings.notchAutoCollapsed = false
        settings.notchCollapseOptOut = true
    }

    private func syncItems() {
        deck.close()
        defer { syncKeepAwakeItem() }
        if settings.menuBarStyle == .ring {
            items.values.forEach { $0.remove() }
            items.removeAll()
            combinedItem?.remove()
            combinedItem = nil
            syncVibeItem()
            return
        }
        if settings.menuBarStyle == .combined {
            items.values.forEach { $0.remove() }
            items.removeAll()
            vibeItem?.remove()
            vibeItem = nil
            if let combinedItem {
                combinedItem.refitAroundNotch()
                combinedItem.refreshLength()
            } else {
                combinedItem = makeItem(.combined)
            }
            return
        }

        combinedItem?.remove()
        combinedItem = nil
        // Reordered in Settings: rebuild every item under new names, right to left, so they land in order.
        if itemGeneration != settings.statusItemGeneration {
            itemGeneration = settings.statusItemGeneration
            items.values.forEach { $0.remove() }
            items.removeAll()
            vibeItem?.remove()
            vibeItem = nil
        }
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
        syncVibeItem()
    }

    /// The Keep Awake item, in either menu bar style. Created last so it sits left of VibeCheck's other items.
    /// Rebuilt with the others on a reorder (`syncItems` removes it first).
    private func syncKeepAwakeItem() {
        if settings.keepAwakeMenuBarItem {
            if keepAwakeItem == nil || keepAwakeItemGeneration != settings.statusItemGeneration {
                keepAwakeItem?.remove()
                keepAwakeItemGeneration = settings.statusItemGeneration
                keepAwakeItem = StatusItemController(kind: .keepAwake, stats: stats, settings: settings) { [weak self] item in
                    self?.keepAwakeClicked(item)
                }
            }
            keepAwakeItem?.refreshLength()
        } else {
            keepAwakeItem?.remove()
            keepAwakeItem = nil
        }
    }
    private var keepAwakeItemGeneration = -1

    /// Click: start (with the default length) or stop. Right-click, ⌃-click or ⌥-click: the full menu.
    private func keepAwakeClicked(_ item: StatusItemController) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true || event?.modifierFlags.contains(.option) == true
        deck.close()
        if wantsMenu {
            item.show(keepAwakeMenu.build())
        } else {
            KeepAwake.shared.toggle()
        }
    }

    /// Separate items: the standalone item holds the ring and/or the keep-awake cup. Created after the
    /// modules so it sits to their left.
    private func syncVibeItem() {
        guard settings.menuBarStyle != .combined else { return }
        let needed = settings.ringVisible || AwakeCup.isShown(settings)
        if needed, vibeItem == nil {
            vibeItem = makeItem(.vibe)
        } else if !needed {
            vibeItem?.remove()
            vibeItem = nil
        }
        vibeItem?.refreshLength()
    }

    private func configureHotkeys() {
        if settings.hotkeysEnabled {
            HotkeyManager.shared.register(modifier: settings.hotkeyModifier, keepAwake: settings.keepAwakeHotkey)
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

    /// Opens the deck on the home grid or a module (used by the Shortcuts action).
    func openDeck(_ module: Module?) {
        let target = module.flatMap { settings.isEnabled($0) ? $0 : nil }
        let route: DeckRoute = target.map { .module($0) } ?? .home
        guard let button = (combinedItem ?? target.flatMap { items[$0] } ?? vibeItem ?? items.values.first)?.button else { return }
        deck.open(from: button, route: route)
    }

    func showSettings(_ section: SettingsSection? = nil) {
        if let section { SettingsRouter.shared.open(section) }
        deck.close()
        if settingsWindow == nil {
            let view = SettingsView(onTestNotification: { [weak self] in self?.alerts.sendTest() })
                .environment(settings).environment(stats)
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: controller)
            window.title = String(localized: "VibeCheck Settings")
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
                    NSLog("%@", "VibeCheck deck-demo item \(item.kind) shown=\(item.fit.visibleCount.map(String.init) ?? "all"): window=\(NSStringFromRect(window.frame)) buttonOnScreen=\(NSStringFromRect(inScreen)) screen=\(NSStringFromRect(window.screen?.frame ?? .zero)) visible=\(NSStringFromRect(window.screen?.visibleFrame ?? .zero))")
                }
                // What the combined item would show beside the notch, using the real label widths.
                let spacing = self.settings.menuBarSpacing
                let widths = self.settings.orderedModules.map { module in
                    NSHostingView(rootView: MenuBarLabel(module: module, padded: false)
                        .environment(self.stats).environment(self.settings)).fittingSize.width
                }
                let chip = NSHostingView(rootView: HiddenCountChip(count: 8)).fittingSize.width
                for room in [189.0, 300.0] {
                    let fitted = NotchFit.visibleCount(itemWidths: widths, fixed: 16 + spacing.padding * 2, gap: spacing.between,
                                                       chipWidth: chip, available: room)
                    let count = NotchFit.capped(fitted: fitted, total: widths.count, cap: self.settings.notchMaxStats)
                    let names = count.map { self.settings.orderedModules.prefix($0).map(\.title).joined(separator: ", ") } ?? "all"
                    NSLog("%@", "VibeCheck deck-demo notch-fit room=\(Int(room)): \(names) + \(count.map { "+\(self.settings.orderedModules.count - $0)" } ?? "none")")
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
                let window = NSApp.windows.first { $0.title == String(localized: "VibeCheck Settings") }
                NSLog("%@", "VibeCheck deck-demo settings-window: visible=\(window?.isVisible ?? false) frame=\(NSStringFromRect(window?.frame ?? .zero)) vibe=\(self.stats.vibe.vibe.title) verdict=\(self.stats.vibe.verdict)")
                window?.close()
            }),
        ]
        for (time, name, action) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) { log(name); action() }
        }
    }
}
