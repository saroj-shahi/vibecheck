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
            let status = NSMenuItem(title: session.focus ? "Focusing, \(session.remaining(now: now))"
                                                         : "Awake \(session.remaining(now: now))", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(ActionItem(session.focus ? "End Focus Session" : "Stop Keeping Awake") { awake.stop() })
        } else {
            menu.addItem(ActionItem("Start (\(AwakePreset.title(settings.keepAwakeDefaultMinutes)))") {
                awake.start(minutes: settings.keepAwakeDefaultMinutes)
            })
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: awake.isActive ? "Start Over" : "Keep Awake"))
        for minutes in AwakePreset.minutes {
            menu.addItem(ActionItem(AwakePreset.title(minutes)) { awake.start(minutes: minutes) })
        }
        let until = NSMenuItem(title: "Until", action: nil, keyEquivalent: "")
        let untilMenu = NSMenu()
        for date in AwakePreset.upcomingHours(after: now) {
            untilMenu.addItem(ActionItem(date.formatted(date: .omitted, time: .shortened)) { awake.start(.at(date)) })
        }
        until.submenu = untilMenu
        menu.addItem(until)

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Focus"))
        for minutes in FocusPreset.minutes {
            menu.addItem(ActionItem("Focus for \(minutes) Minutes") { awake.startFocus(minutes: minutes) })
        }

        menu.addItem(.separator())
        menu.addItem(ActionItem("Keep the Display On", state: settings.keepAwakeDisplayOn ? .on : .off) {
            settings.keepAwakeDisplayOn.toggle()
        })
        menu.addItem(ActionItem("Keep Awake Settings…") {
            (NSApp.delegate as? AppDelegate)?.showSettings(.keepAwake)
        })
        return menu
    }

    /// Titles in order, for tests.
    func titles(now: Date = Date()) -> [String] {
        build(now: now).items.map { $0.isSeparatorItem ? "—" : $0.title }
    }
}
