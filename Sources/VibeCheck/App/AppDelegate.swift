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
        /// Standalone next calendar event item: shows upcoming event + countdown, click opens Clock or joins call.
        case nextEvent
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
        switch kind {
        case .single(let module): return .module(module)
        case .nextEvent: return .module(.clock)
        default: return .home
        }
    }

    /// Next event item only: event IDs temporarily hidden from the menu bar by the user.
    var dismissedNextEventIDs: Set<String> = []

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
        case .nextEvent:
            item.autosaveName = AppSettings.autosaveName("nextevent", generation: settings.statusItemGeneration)
            label = AnyView(NextEventMenuBarLabel(dismissedEventIDs: []))
        }
        // macOS restores a hidden item's visibility by autosave name; every item we create is meant to show.
        item.isVisible = true
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
            if kind == .keepAwake || kind == .nextEvent { button.sendAction(on: [.leftMouseUp, .rightMouseUp]) }
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
        case .single, .keepAwake, .nextEvent: return nil
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
        let badge = VibeItemLabel.shownBadge(stats.vibe, ringShown: settings.menuBar.ringVisible, isShown: settings.showsInMenuBar)
        let shape = Self.badgeShape(badge)
        guard shape != measuredBadge else { return }
        measuredBadge = shape
        refreshLength()
    }

    // MARK: Notch auto-fit (combined item)

    private var placementObservers: [(NotificationCenter, NSObjectProtocol)] = []

    private func observePlacement() {
        removePlacementObservers()
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let refit: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refitAroundNotch() }
        }
        if let window = item.button?.window {
            placementObservers.append((center, center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main, using: refit)))
            placementObservers.append((center, center.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main, using: refit)))
        }
        placementObservers.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: refit)))
        placementObservers.append((workspace, workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                                    object: nil, queue: .main, using: refit)))
        // The item gets its final position shortly after launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refitAroundNotch() }
    }

    private func removePlacementObservers() {
        for (center, token) in placementObservers { center.removeObserver(token) }
        placementObservers.removeAll()
    }

    /// Shows only as many stats as fit between the camera notch and the item's right edge (which stays put
    /// as the item resizes). On displays without a notch, or with the setting off, everything is shown.
    func refitAroundNotch() {
        guard kind == .combined else { return }
        var limit: Int?
        if settings.menuBar.autoFitNotch, let button = item.button, let window = button.window, let screen = window.screen {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            if let available = NotchFit.availableWidth(itemRect: rect, notchRight: screen.auxiliaryTopRightArea,
                                                       notchLeft: screen.auxiliaryTopLeftArea) {
                let spacing = settings.menuBar.spacing
                let widths = settings.orderedModules.map { module in
                    NSHostingView(rootView: MenuBarLabel(module: module, padded: false)
                        .environment(stats).environment(settings)).fittingSize.width
                }
                let chip = NSHostingView(rootView: HiddenCountChip(count: 8)).fittingSize.width
                let ring: CGFloat = settings.menuBar.ringVisible ? 16 : 0
                let cup = AwakeCup.isShown(settings) ? NSHostingView(rootView: AwakeCup().environment(settings)).fittingSize.width + spacing.between : 0
                let fitted = NotchFit.visibleCount(itemWidths: widths, fixed: ring + cup + spacing.padding * 2,
                                                   gap: spacing.between, chipWidth: chip, available: available)
                limit = NotchFit.capped(fitted: fitted, total: widths.count, cap: settings.menuBar.notchMaxStats)
            }
        }
        guard limit != fit.visibleCount else { return }
        fit.visibleCount = limit
        refreshLength()
    }

    /// Window state for the launch visibility check.
    var visibilityProbe: MenuBarVisibility.Probe {
        let window = item.button?.window
        return MenuBarVisibility.Probe(hasWindow: window != nil, isVisible: window?.isVisible ?? false, frame: window?.frame ?? .zero)
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
        case .nextEvent: String(localized: "Next Event")
        }
    }

    /// Rebinds the Next Event label after dismissed events change and re-measures its width.
    func updateNextEventLabel(dismissed: Set<String>) {
        guard kind == .nextEvent, let button = item.button else { return }
        dismissedNextEventIDs = dismissed
        let updated = AnyView(NextEventMenuBarLabel(dismissedEventIDs: dismissed).environment(stats).environment(settings))
        labelView = updated
        if let host = button.subviews.first(where: { $0 is PassthroughHostingView<AnyView> }) as? PassthroughHostingView<AnyView> {
            host.rootView = updated
        }
        refreshLength()
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

    /// Removing an item makes macOS forget where the user put it; hiding keeps its place among the
    /// other menu bar items, so turning it back on puts it right where it was.
    var isShown: Bool {
        get { item.isVisible }
        set { item.isVisible = newValue }
    }

    func remove() {
        removePlacementObservers()
        NSStatusBar.system.removeStatusItem(item)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let stats = SystemStats()
    let launchedAt = Date()
    let settings = AppSettings.shared
    private let alerts = AlertEngine()
    lazy var deck = DeckController(stats: stats, settings: settings)
    private(set) var items: [Module: StatusItemController] = [:]
    private(set) var combinedItem: StatusItemController?
    /// The standalone ring shown with separate items.
    private(set) var vibeItem: StatusItemController?
    private var settingsWindow: NSWindow?
    /// The standalone Keep Awake item, when it's switched on in Settings.
    private var keepAwakeItem: StatusItemController?
    /// The standalone Next Event item, when enabled and an upcoming event is within lookahead.
    private var nextEventItem: StatusItemController?
    /// Items turned off in Settings, hidden rather than removed so they come back in the same spot.
    private var parkedItems: [Module: StatusItemController] = [:]
    private var parkedVibeItem: StatusItemController?
    private var parkedKeepAwakeItem: StatusItemController?
    private var parkedNextEventItem: StatusItemController?
    private var dismissedNextEventIDs: Set<String> = []
    private var nextEventTimer: Timer?
    private let keepAwakeMenu = KeepAwakeMenu()
    /// Generation the separate items were created with; a reorder in Settings bumps it.
    private var itemGeneration = 0
    private var agentWatch = AgentWatch()

    func applicationDidFinishLaunching(_ notification: Notification) {
        alerts.log = NotificationLog.shared
        UpdateChecker.shared.onNewVersion = { [weak self] release in
            self?.alerts.notify(title: String(localized: "VibeCheck \(release.version) is out"),
                                body: String(localized: "Update in Terminal: \(UpdateChecker.brewCommand). Settings › About has the other way. Click for what's new."),
                                kind: .alert, url: release.pageURL)
        }
        UpdateChecker.shared.start()
        VibeHooks.shared.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            MainActor.assumeIsolated { self?.checkMenuBarVisibleAtLaunch() }
        }
        let automated = CommandLine.arguments.contains("--deck-demo") || CommandLine.arguments.contains("--render-screenshots")
        if !automated { StarPrompt.shared.start() }
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
            WidgetPublisher.shared.tick(stats: self.stats)
            StatusPublisher.shared.tick(stats: self.stats)
        }
        KeepAwake.shared.batteryProvider = { [unowned stats] in stats.battery }
        KeepAwake.shared.onSessionEnded = { [weak self] reason in
            guard let self else { return }
            // A finished focus session always says so; other endings follow the keep-awake setting.
            if reason == .focusDone {
                self.alerts.notify(title: String(localized: "Focus session done"), body: String(localized: "Take a break. Your Mac can sleep again."), kind: .keepAwake)
                return
            }
            guard reason.notifies, self.settings.keepAwake.notify else { return }
            self.alerts.notify(title: String(localized: "Keep awake ended"), body: String(localized: "\(reason.message) Your Mac can sleep again."), kind: .keepAwake)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { KeepAwake.shared.check() }
        }
        HotkeyManager.shared.onExtra = { [weak self] extra in
            switch extra {
            case .keepAwake: KeepAwake.shared.toggle()
            case .clipboard: self?.openClipboard()
            case .findCursor: CursorFinder.flash()
            case .joinVideoCall:
                if CalendarStore.shared.joinNextVideoCall() == nil { NSSound.beep() }
            }
        }
        ClipboardHistory.shared.start()
        if settings.keepAwake.atLaunch { KeepAwake.shared.start(minutes: settings.keepAwake.defaultMinutes) }
        KeepAwake.shared.check() // triggers (plugged in, external display) apply right away
        stats.start(interval: settings.refreshInterval)
        itemGeneration = settings.statusItemGeneration
        syncItems()
        HotkeyManager.shared.onTrigger = { [weak self] module in self?.openFromShortcut(module) }
        configureHotkeys()
        WeatherStore.shared.refresh()
        if settings.clock.showCalendarEvents || settings.clock.nextEventInMenuBar || settings.clock.meetingAlertStyle != .off {
            CalendarStore.shared.ensureStarted()
        }
        MeetingAlertManager.shared.start(alerts: alerts)
        HourlyChimeManager.shared.start()
        NotificationCenter.default.addObserver(forName: .vibeCheckCalendarChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNextEventItem() }
        }
        AgentUsageStore.shared.start()
        BluetoothSnooze.shared.isEnabled = { [unowned settings] in settings.keepAwake.bluetoothOffWhileAsleep }
        BluetoothSnooze.shared.start()
        SleepDrain.shared.start()

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
        if let idx = CommandLine.arguments.firstIndex(of: "--render-screenshots") {
            let dir = CommandLine.arguments.indices.contains(idx + 1) ? CommandLine.arguments[idx + 1] : "docs/screenshots"
            runRenderScreenshots(to: dir)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MeetingAlertManager.shared.stop()
        HourlyChimeManager.shared.stop()
        KeyboardCleaner.shared.stop()
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
        guard settings.keepAwake.notifyAgentFinished else { return }
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
        guard NotchHideWatch.mayCollapse(separate: settings.menuBar.style == .separate, autoFit: settings.menuBar.autoFitNotch,
                                         optedOut: settings.menuBar.notchCollapseOptOut) else {
            notchWatch.hiddenSince = nil
            return
        }
        let separate = Array(items.values) + [vibeItem, keepAwakeItem].compactMap { $0 }
        let hidden = separate.contains { $0.isHiddenByNotch }
        guard notchWatch.update(hidden: hidden, now: Date()) else { return }
        notchWatch.hiddenSince = nil
        settings.menuBar.notchAutoCollapsed = true
        settings.menuBar.style = .combined
        if !settings.menuBar.notchNoticeShown {
            settings.menuBar.notchNoticeShown = true
            alerts.notify(title: NotchHideWatch.noticeTitle, body: NotchHideWatch.noticeBody, kind: .alert)
        }
    }

    /// About 3 s after launch: if macOS is hiding every status item ("Allow in the Menu Bar" off), say so once.
    /// The notch case is NotchHideWatch's job, and an auto-hidden or full-screen menu bar proves nothing.
    private func checkMenuBarVisibleAtLaunch(secondLook: Bool = false) {
        guard !UserDefaults.standard.bool(forKey: MenuBarVisibility.shownKey), NSMenu.menuBarVisible() else { return }
        let all = Array(items.values) + [vibeItem, keepAwakeItem, combinedItem].compactMap { $0 }
        let probes = all.map { (probe: $0.visibilityProbe, notchHidden: $0.isHiddenByNotch) }
        let verdict = MenuBarVisibility.verdict(probes: probes, screenFrames: NSScreen.screens.map(\.frame))
        guard verdict == .hiddenByMacOS else { return }
        // At login the items may not be placed yet: only a second miss 10 s later counts.
        guard secondLook else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                MainActor.assumeIsolated { self?.checkMenuBarVisibleAtLaunch(secondLook: true) }
            }
            return
        }
        UserDefaults.standard.set(true, forKey: MenuBarVisibility.shownKey)
        let alert = NSAlert()
        alert.messageText = MenuBarVisibility.title
        alert.informativeText = MenuBarVisibility.body(verdict)
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Not now"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(MenuBarVisibility.settingsURL) }
    }

    /// The owner switched back to separate items after an automatic collapse: don't collapse again.
    private func noteExplicitStyleChoice() {
        guard settings.menuBar.notchAutoCollapsed, settings.menuBar.style == .separate else { return }
        settings.menuBar.notchAutoCollapsed = false
        settings.menuBar.notchCollapseOptOut = true
    }

    private func syncItems() {
        deck.close()
        defer {
            syncKeepAwakeItem()
            syncNextEventItem()
        }
        if settings.menuBar.style == .ring {
            items.values.forEach { $0.remove() }
            items.removeAll()
            removeParkedModuleItems()
            combinedItem?.remove()
            combinedItem = nil
            syncVibeItem()
            return
        }
        if settings.menuBar.style == .combined {
            items.values.forEach { $0.remove() }
            items.removeAll()
            removeParkedModuleItems()
            vibeItem?.remove()
            vibeItem = nil
            parkedVibeItem?.remove()
            parkedVibeItem = nil
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
            removeParkedModuleItems()
            vibeItem?.remove()
            vibeItem = nil
            parkedVibeItem?.remove()
            parkedVibeItem = nil
        }
        // Insert in reverse so the left-to-right order matches Module.allCases.
        for module in settings.moduleOrder.reversed() {
            let enabled = settings.isEnabled(module)
            if enabled, items[module] == nil {
                if let parked = parkedItems.removeValue(forKey: module) {
                    parked.isShown = true
                    items[module] = parked
                } else {
                    items[module] = makeItem(.single(module))
                }
            } else if !enabled, let existing = items.removeValue(forKey: module) {
                existing.isShown = false
                parkedItems[module] = existing
            }
            items[module]?.refreshLength() // label style or clock format may have changed
        }
        syncVibeItem()
    }

    private func removeParkedModuleItems() {
        parkedItems.values.forEach { $0.remove() }
        parkedItems.removeAll()
    }

    /// The Keep Awake item, in either menu bar style. Created last so it sits left of VibeCheck's other items.
    /// Rebuilt with the others on a reorder (`syncItems` removes it first).
    private func syncKeepAwakeItem() {
        if settings.keepAwake.menuBarItem {
            if keepAwakeItemGeneration != settings.statusItemGeneration {
                keepAwakeItem?.remove()
                keepAwakeItem = nil
                parkedKeepAwakeItem?.remove()
                parkedKeepAwakeItem = nil
                keepAwakeItemGeneration = settings.statusItemGeneration
            }
            if keepAwakeItem == nil, let parked = parkedKeepAwakeItem {
                parked.isShown = true
                keepAwakeItem = parked
                parkedKeepAwakeItem = nil
            }
            if keepAwakeItem == nil {
                keepAwakeItem = StatusItemController(kind: .keepAwake, stats: stats, settings: settings) { [weak self] item in
                    self?.keepAwakeClicked(item)
                }
            }
            keepAwakeItem?.refreshLength()
        } else if let item = keepAwakeItem {
            item.isShown = false
            parkedKeepAwakeItem = item
            keepAwakeItem = nil
        }
    }
    private var keepAwakeItemGeneration = -1
    private var nextEventItemGeneration = -1

    /// Optional standalone Next Event item in the menu bar. Hides cleanly when no event is within lookahead.
    private func syncNextEventItem() {
        let clock = settings.clock
        let display = clock.nextEventInMenuBar && CalendarStore.shared.access == .granted
            ? NextEventLogic.display(events: CalendarStore.shared.events,
                                     now: Date(),
                                     hiddenCalendarIDs: clock.hiddenCalendarIDs,
                                     dismissedEventIDs: dismissedNextEventIDs,
                                     onlyVideoCalls: clock.nextEventOnlyVideoCalls,
                                     showDuringEntireEvent: clock.nextEventShowDuringEntireEvent,
                                     lookaheadMinutes: clock.nextEventLookaheadHours * 60)
            : nil

        scheduleNextEventTimer(enabled: clock.nextEventInMenuBar && CalendarStore.shared.access == .granted)

        if let display {
            if nextEventItemGeneration != settings.statusItemGeneration {
                nextEventItem?.remove()
                nextEventItem = nil
                parkedNextEventItem?.remove()
                parkedNextEventItem = nil
                nextEventItemGeneration = settings.statusItemGeneration
            }
            if nextEventItem == nil, let parked = parkedNextEventItem {
                parked.isShown = true
                nextEventItem = parked
                parkedNextEventItem = nil
            }
            if nextEventItem == nil {
                nextEventItem = StatusItemController(kind: .nextEvent, stats: stats, settings: settings) { [weak self] item in
                    self?.nextEventClicked(item)
                }
            }
            nextEventItem?.updateNextEventLabel(dismissed: dismissedNextEventIDs)
            nextEventItem?.button?.toolTip = "\(display.event.title) (\(display.countdown))"
        } else if let item = nextEventItem {
            item.isShown = false
            parkedNextEventItem = item
            nextEventItem = nil
        }
    }

    private func scheduleNextEventTimer(enabled: Bool) {
        nextEventTimer?.invalidate()
        nextEventTimer = nil
        guard enabled else { return }
        // Fire cleanly right after the next minute boundary so countdowns and item appearance stay in sync.
        let now = Date()
        let secondsIntoMinute = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
        let delay = max(1, 60.5 - secondsIntoMinute)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNextEventItem() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        nextEventTimer = timer
    }

    private func nextEventClicked(_ item: StatusItemController) {
        let clock = settings.clock
        let now = Date()
        let display = NextEventLogic.display(events: CalendarStore.shared.events,
                                             now: now,
                                             hiddenCalendarIDs: clock.hiddenCalendarIDs,
                                             dismissedEventIDs: dismissedNextEventIDs,
                                             onlyVideoCalls: clock.nextEventOnlyVideoCalls,
                                             showDuringEntireEvent: clock.nextEventShowDuringEntireEvent,
                                             lookaheadMinutes: clock.nextEventLookaheadHours * 60)
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu, let display {
            deck.close()
            item.show(buildNextEventMenu(for: display.event))
            return
        }
        // Clicking the inline trailing "Join" pill joins the video call directly.
        if let display,
           display.showsJoinPill(at: now, enabled: clock.nextEventShowJoinButton),
           let link = display.event.videoCall,
           let button = item.button,
           let event {
            let local = button.convert(event.locationInWindow, from: nil)
            if local.x >= button.bounds.width - (NextEventMenuBarLabel.joinPillWidth + 8) {
                deck.close()
                NSWorkspace.shared.open(link.url)
                return
            }
        }
        if clock.nextEventClickToJoin, let display, display.canQuickJoin(at: now), let link = display.event.videoCall {
            deck.close()
            NSWorkspace.shared.open(link.url)
            return
        }
        guard let button = item.button else { return }
        deck.toggle(from: button, route: .module(.clock))
    }

    private func buildNextEventMenu(for event: CalendarEvent) -> NSMenu {
        let menu = NSMenu()
        if let link = event.videoCall {
            let join = NSMenuItem(title: String(localized: "Join \(link.service.title)"), action: #selector(menuJoinCall(_:)), keyEquivalent: "")
            join.target = self
            join.representedObject = link.url
            menu.addItem(join)
            menu.addItem(.separator())
        }
        let openCal = NSMenuItem(title: String(localized: "Open in Calendar"), action: #selector(menuOpenCalendarDate(_:)), keyEquivalent: "")
        openCal.target = self
        openCal.representedObject = event.startDate
        menu.addItem(openCal)

        let openPanel = NSMenuItem(title: String(localized: "Open Date & Time"), action: #selector(menuOpenClockPanel), keyEquivalent: "")
        openPanel.target = self
        menu.addItem(openPanel)

        menu.addItem(.separator())
        let hide = NSMenuItem(title: String(localized: "Hide This Event from Menu Bar"), action: #selector(menuHideNextEvent(_:)), keyEquivalent: "")
        hide.target = self
        hide.representedObject = event.id
        menu.addItem(hide)
        return menu
    }

    @objc private func menuJoinCall(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func menuOpenCalendarDate(_ sender: NSMenuItem) {
        CalendarDateHelper.openCalendarApp(at: sender.representedObject as? Date)
    }

    @objc private func menuOpenClockPanel() {
        openDeck(.clock)
    }

    @objc private func menuHideNextEvent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        dismissedNextEventIDs.insert(id)
        syncNextEventItem()
    }

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
        guard settings.menuBar.style != .combined else { return }
        let needed = settings.menuBar.ringVisible || AwakeCup.isShown(settings)
        if needed, vibeItem == nil {
            if let parked = parkedVibeItem {
                parked.isShown = true
                vibeItem = parked
                parkedVibeItem = nil
            } else {
                vibeItem = makeItem(.vibe)
            }
        } else if !needed, let item = vibeItem {
            item.isShown = false
            parkedVibeItem = item
            vibeItem = nil
        }
        vibeItem?.refreshLength()
    }

    private func configureHotkeys() {
        if settings.hotkeysEnabled {
            var extras: Set<HotkeyManager.Extra> = []
            if settings.keepAwake.hotkey { extras.insert(.keepAwake) }
            if settings.clipboardHotkey { extras.insert(.clipboard) }
            if settings.findCursorHotkey { extras.insert(.findCursor) }
            if settings.joinCallHotkey { extras.insert(.joinVideoCall) }
            HotkeyManager.shared.register(modifier: settings.hotkeyModifier, extras: extras)
        } else {
            HotkeyManager.shared.unregisterAll()
        }
    }

    /// Global shortcut: open the deck on that module, or close it if that module is already showing.
    private func openFromShortcut(_ module: Module) {
        guard settings.isEnabled(module) else { NSSound.beep(); return }
        if deck.isVisible, deck.route == .module(module) { deck.close(); return }
        guard let button = (combinedItem ?? items[module] ?? vibeItem ?? items.values.first)?.button else { return }
        deck.open(from: button, route: .module(module))
    }

    /// Opens the deck on the home grid or a module (used by the Shortcuts action).
    func openDeck(_ module: Module?) {
        let target = module.flatMap { settings.isEnabled($0) ? $0 : nil }
        let route: DeckRoute = target.map { .module($0) } ?? .home
        guard let button = (combinedItem ?? target.flatMap { items[$0] } ?? vibeItem ?? items.values.first)?.button else { return }
        deck.open(from: button, route: route)
    }

    /// Global shortcut: the palette in clipboard mode (snippets and history), or close it if already showing.
    private func openClipboard() {
        if deck.isVisible, deck.model.paletteQuery == "clip " { deck.close(); return }
        openDeck(nil)
        deck.model.openPalette("clip ")
    }

    static let settingsWindowID = NSUserInterfaceItemIdentifier("VibeCheckSettings")

    /// Ensures standard Edit & Window shortcuts (⌘C/⌘V/⌘A/⌘Z/⌘W) work inside Settings text fields
    /// even though VibeCheck runs with `.accessory` activation policy.
    private func ensureStandardMenus() {
        guard NSApp.mainMenu == nil else { return }
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "Quit VibeCheck"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenu.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenu.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    func showSettings(_ section: SettingsSection? = nil) {
        if let section { SettingsRouter.shared.open(section) }
        deck.close()
        ensureStandardMenus()
        if settingsWindow == nil {
            let view = SettingsView(onTestNotification: { [weak self] in self?.alerts.sendTest() })
                .environment(settings).environment(stats)
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: controller)
            window.identifier = Self.settingsWindowID
            window.delegate = self
            window.title = (SettingsRouter.shared.section ?? .menuBar).title
            // Dim minimize and zoom per macOS Settings HIG: quick to reopen with ⌘, and never belongs in the Dock.
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.collectionBehavior.insert(.fullScreenNone)
            let toolbar = NSToolbar(identifier: "VibeCheckSettingsToolbar")
            toolbar.displayMode = .iconOnly
            toolbar.showsBaselineSeparator = true
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            window.titlebarSeparatorStyle = .automatic
            window.setContentSize(NSSize(width: 960, height: 680))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        } else if let active = SettingsRouter.shared.section {
            settingsWindow?.title = active.title
        }
        // Show a Dock icon while Settings is open, and remove it again when Settings closes.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.settingsWindow?.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
