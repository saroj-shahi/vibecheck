import AppKit

/// The Keep Awake item's right-click menu: the same choices as the deck's cup menu, as a native menu.
@MainActor
final class KeepAwakeMenu: NSObject {
    /// Menu item that runs a closure.
    private final class ActionItem: NSMenuItem {
        private let run: () -> Void

        init(_ title: String, state: NSControl.StateValue = .off, enabled: Bool = true, _ run: @escaping () -> Void) {
            self.run = run
            super.init(title: title, action: enabled ? #selector(fire) : nil, keyEquivalent: "")
            self.state = state
            target = self
            isEnabled = enabled
        }

        @available(*, unavailable) required init(coder: NSCoder) { fatalError() }

        @objc private func fire() { run() }
    }

    func build(now: Date = Date()) -> NSMenu {
        let awake = KeepAwake.shared
        let settings = AppSettings.shared
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let session = awake.session {
            let status = NSMenuItem(title: session.focus ? String(localized: "Focusing, \(session.remaining(now: now))")
                                                         : String(localized: "Awake \(session.remaining(now: now))"), action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(ActionItem(session.focus ? String(localized: "End Focus Session") : String(localized: "Stop Keeping Awake")) { awake.stop() })
        } else {
            menu.addItem(ActionItem(String(localized: "Start (\(AwakePreset.title(settings.keepAwake.defaultMinutes)))")) {
                awake.start(minutes: settings.keepAwake.defaultMinutes)
            })
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: awake.isActive ? String(localized: "Start Over") : String(localized: "Keep Awake")))
        for minutes in AwakePreset.minutes {
            menu.addItem(ActionItem(AwakePreset.title(minutes)) { awake.start(minutes: minutes) })
        }
        let until = NSMenuItem(title: String(localized: "Until"), action: nil, keyEquivalent: "")
        let untilMenu = NSMenu()
        for date in AwakePreset.upcomingHours(after: now) {
            untilMenu.addItem(ActionItem(date.formatted(date: .omitted, time: .shortened)) { awake.start(.at(date)) })
        }
        until.submenu = untilMenu
        menu.addItem(until)
        let running = NSMenuItem(title: String(localized: "While an App Is Running"), action: nil, keyEquivalent: "")
        let runningMenu = NSMenu()
        let apps = KeepAwake.runningApps()
        if apps.isEmpty { runningMenu.addItem(ActionItem(String(localized: "No apps running"), enabled: false) {}) }
        for app in apps {
            runningMenu.addItem(ActionItem(app.name) { awake.start(.whileRunning(bundleID: app.bundleID, name: app.name)) })
        }
        running.submenu = runningMenu
        menu.addItem(running)

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: String(localized: "Focus")))
        for minutes in FocusPreset.minutes {
            menu.addItem(ActionItem(String(localized: "Focus for \(minutes) Minutes")) { awake.startFocus(minutes: minutes) })
        }

        menu.addItem(.separator())
        menu.addItem(ActionItem(String(localized: "Keep the Display On"), state: settings.keepAwake.displayOn ? .on : .off) {
            settings.keepAwake.displayOn.toggle()
        })
        menu.addItem(ActionItem(String(localized: "Keep Awake Settings…")) {
            (NSApp.delegate as? AppDelegate)?.showSettings(.keepAwake)
        })
        return menu
    }

    /// Titles in order, for tests.
    func titles(now: Date = Date()) -> [String] {
        build(now: now).items.map { $0.isSeparatorItem ? "—" : $0.title }
    }
}
