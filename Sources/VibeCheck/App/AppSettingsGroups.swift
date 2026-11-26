import Foundation
import Observation
import SwiftUI

/// Writes one setting under its key; a structural change also tells the menu bar to rebuild and re-measure.
/// Shared by `AppSettings` and its groups so every key is saved the same way.
struct SettingsWriter {
    let defaults: UserDefaults

    func save(_ value: Any, _ key: String, structural: Bool) {
        defaults.set(value, forKey: key)
        if structural { NotificationCenter.default.post(name: .vibeCheckSettingsChanged, object: nil) }
    }
}

/// Menu bar look and notch behaviour. Keys are the same flat keys as before the grouping.
@Observable
@MainActor
final class MenuBarGroup {
    @ObservationIgnored private let writer: SettingsWriter

    var style: MenuBarStyle {
        didSet { writer.save(style.rawValue, "menuBarStyle", structural: true) }
    }
    var spacing: MenuBarSpacing {
        didSet { writer.save(spacing.rawValue, "menuBarSpacing", structural: true) }
    }
    var autoFitNotch: Bool {
        didSet { writer.save(autoFitNotch, "autoFitNotch", structural: true) }
    }
    /// At most this many stats beside the notch (0 = as many as fit).
    var notchMaxStats: Int {
        didSet { writer.save(notchMaxStats, "notchMaxStats", structural: true) }
    }
    /// Notch auto-collapse state (per Mac, not part of backups): the one-time notice was shown; VibeCheck
    /// switched to the combined item by itself; the owner switched back to separate items, so don't again.
    var notchNoticeShown: Bool {
        didSet { writer.save(notchNoticeShown, "notchNoticeShown", structural: false) }
    }
    var notchAutoCollapsed: Bool {
        didSet { writer.save(notchAutoCollapsed, "notchAutoCollapsed", structural: false) }
    }
    var notchCollapseOptOut: Bool {
        didSet { writer.save(notchCollapseOptOut, "notchCollapseOptOut", structural: false) }
    }
    var showVibeRing: Bool {
        didSet { writer.save(showVibeRing, "showVibeRing", structural: true) }
    }
    var colorful: Bool {
        didSet { writer.save(colorful, "colorfulMenuBar", structural: false) }
    }
    /// Menu bar ring shows the vibe color even while vibing (off: monochrome until mid / cooked).
    var alwaysColorRing: Bool {
        didSet { writer.save(alwaysColorRing, "alwaysColorRing", structural: false) }
    }
    /// The ring pulses while a hook (an agent) is waiting for you.
    var pulseOnNeedsInput: Bool {
        didSet { writer.save(pulseOnNeedsInput, "pulseOnAgentNeedsInput", structural: false) }
    }
    /// The ring is drawn when it's on, and always in the ring-only style.
    var ringVisible: Bool { showVibeRing || style == .ring }

    /// `isNewInstall`: no saved modules yet. New installs start with just the vibe ring (the deck has
    /// everything else); an existing install without a stored choice keeps the combined item.
    init(defaults: UserDefaults, isNewInstall: Bool) {
        writer = SettingsWriter(defaults: defaults)
        style = defaults.string(forKey: "menuBarStyle").flatMap(MenuBarStyle.init(rawValue:))
            ?? (isNewInstall ? .ring : .combined)
        spacing = defaults.string(forKey: "menuBarSpacing").flatMap(MenuBarSpacing.init(rawValue:)) ?? .normal
        autoFitNotch = defaults.object(forKey: "autoFitNotch") as? Bool ?? true
        notchMaxStats = defaults.integer(forKey: "notchMaxStats")
        notchNoticeShown = defaults.bool(forKey: "notchNoticeShown")
        notchAutoCollapsed = defaults.bool(forKey: "notchAutoCollapsed")
        notchCollapseOptOut = defaults.bool(forKey: "notchCollapseOptOut")
        showVibeRing = defaults.object(forKey: "showVibeRing") as? Bool ?? true
        colorful = defaults.object(forKey: "colorfulMenuBar") as? Bool ?? true
        alwaysColorRing = defaults.bool(forKey: "alwaysColorRing")
        pulseOnNeedsInput = defaults.bool(forKey: "pulseOnAgentNeedsInput")
    }
}

@Observable
@MainActor
final class ClockGroup {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let writer: SettingsWriter

    var format: ClockFormat {
        didSet { writer.save(format.rawValue, "clockFormat", structural: true) }
    }
    var customFormat: String {
        didSet { writer.save(customFormat, "clockCustomFormat", structural: true) }
    }
    var showSeconds: Bool {
        didSet { writer.save(showSeconds, "clockShowSeconds", structural: true) }
    }
    var showWeekNumberInMenuBar: Bool {
        didSet { writer.save(showWeekNumberInMenuBar, "clockShowWeekNumberInMenuBar", structural: true) }
    }
    var showWeekNumbersInCalendar: Bool {
        didSet { writer.save(showWeekNumbersInCalendar, "clockShowWeekNumbersInCalendar", structural: false) }
    }
    /// What the menu bar calendar icon shows (date, weekday & date, week & date, or week number).
    var calendarIconStyle: CalendarIconStyle {
        didSet { writer.save(calendarIconStyle.rawValue, "clockCalendarIconStyle", structural: true) }
    }
    /// User-dragged Date & Time popover height (0 = fit content automatically).
    var panelHeight: Double {
        didSet {
            let clamped = panelHeight <= 0 ? 0 : min(max(panelHeight, 260), 1400)
            if clamped != panelHeight { panelHeight = clamped; return }
            writer.save(panelHeight, "clockPanelHeight", structural: false)
        }
    }
    /// Opt-in Apple Calendar events in the Clock panel (asks for Calendar access only when enabled).
    var showCalendarEvents: Bool {
        didSet {
            writer.save(showCalendarEvents, "clockShowCalendarEvents", structural: false)
            if showCalendarEvents { CalendarStore.shared.activate(requestAccess: true) }
        }
    }
    /// Agenda lookahead in days (1, 3, 7 or 14).
    var calendarDaysAhead: Int {
        didSet { writer.save(calendarDaysAhead, "clockCalendarDaysAhead", structural: false) }
    }
    var showAllDayEvents: Bool {
        didSet { writer.save(showAllDayEvents, "clockShowAllDayEvents", structural: false) }
    }
    var hidePastEventsToday: Bool {
        didSet { writer.save(hidePastEventsToday, "clockHidePastEventsToday", structural: false) }
    }
    /// Show dated Apple Reminders alongside calendar events in the Clock agenda.
    var showRemindersInAgenda: Bool {
        didSet {
            writer.save(showRemindersInAgenda, "clockShowRemindersInAgenda", structural: false)
            if showRemindersInAgenda { RemindersStore.shared.activate(requestAccess: true) }
        }
    }
    /// Calendars unchecked by the user (per Mac, not in settings backup).
    var hiddenCalendarIDs: Set<String> {
        didSet {
            defaults.set(Array(hiddenCalendarIDs), forKey: "clockHiddenCalendarIDs")
            NotificationCenter.default.post(name: .vibeCheckCalendarChanged, object: nil)
        }
    }
    /// Standalone "Next Event" item in the menu bar (off by default).
    var nextEventInMenuBar: Bool {
        didSet {
            writer.save(nextEventInMenuBar, "clockNextEventInMenuBar", structural: true)
            if nextEventInMenuBar {
                if !showCalendarEvents { showCalendarEvents = true }
                CalendarStore.shared.activate(requestAccess: true)
            }
        }
    }
    var nextEventShowTitle: Bool {
        didSet { writer.save(nextEventShowTitle, "clockNextEventShowTitle", structural: true) }
    }
    var nextEventOnlyVideoCalls: Bool {
        didSet { writer.save(nextEventOnlyVideoCalls, "clockNextEventOnlyVideoCalls", structural: true) }
    }
    var nextEventShowDuringEntireEvent: Bool {
        didSet { writer.save(nextEventShowDuringEntireEvent, "clockNextEventShowDuringEntireEvent", structural: true) }
    }
    var nextEventClickToJoin: Bool {
        didSet { writer.save(nextEventClickToJoin, "clockNextEventClickToJoin", structural: false) }
    }
    /// Show an inline "Join" button inside the Next Event menu bar item for upcoming/active video calls.
    var nextEventShowJoinButton: Bool {
        didSet { writer.save(nextEventShowJoinButton, "clockNextEventShowJoinButton", structural: true) }
    }
    var nextEventMaxWidth: Int {
        didSet { writer.save(nextEventMaxWidth, "clockNextEventMaxWidth", structural: true) }
    }
    var nextEventLookaheadHours: Int {
        didSet { writer.save(nextEventLookaheadHours, "clockNextEventLookaheadHours", structural: true) }
    }
    /// Fullscreen or banner alerts right before meetings start.
    var meetingAlertStyle: MeetingAlertStyle {
        didSet {
            writer.save(meetingAlertStyle.rawValue, "clockMeetingAlertStyle", structural: true)
            if meetingAlertStyle != .off {
                if !showCalendarEvents { showCalendarEvents = true }
                CalendarStore.shared.activate(requestAccess: true)
            }
        }
    }
    var meetingAlertLeadMinutes: Int {
        didSet { writer.save(meetingAlertLeadMinutes, "clockMeetingAlertLeadMinutes", structural: true) }
    }
    var meetingAlertOnlyVideoCalls: Bool {
        didSet { writer.save(meetingAlertOnlyVideoCalls, "clockMeetingAlertOnlyVideoCalls", structural: true) }
    }
    var meetingAlertOnlyWithAlarm: Bool {
        didSet { writer.save(meetingAlertOnlyWithAlarm, "clockMeetingAlertOnlyWithAlarm", structural: true) }
    }
    var meetingAlertSuppressDuringCall: Bool {
        didSet { writer.save(meetingAlertSuppressDuringCall, "clockMeetingAlertSuppressDuringCall", structural: false) }
    }
    var meetingAlertPlaySound: Bool {
        didSet { writer.save(meetingAlertPlaySound, "clockMeetingAlertPlaySound", structural: false) }
    }
    /// Optional subtle chime on the hour or half-hour during active hours.
    var hourlyChimeEnabled: Bool {
        didSet { writer.save(hourlyChimeEnabled, "clockHourlyChimeEnabled", structural: true) }
    }
    var hourlyChimeCadence: ChimeCadence {
        didSet { writer.save(hourlyChimeCadence.rawValue, "clockHourlyChimeCadence", structural: true) }
    }
    var hourlyChimeSound: ChimeSound {
        didSet { writer.save(hourlyChimeSound.rawValue, "clockHourlyChimeSound", structural: false) }
    }
    var hourlyChimeVolume: Double {
        didSet { writer.save(hourlyChimeVolume, "clockHourlyChimeVolume", structural: false) }
    }
    /// Active hours start & end in minutes since midnight (e.g. 9*60 = 09:00, 18*60 = 18:00).
    var hourlyChimeStartMinute: Int {
        didSet { writer.save(hourlyChimeStartMinute, "clockHourlyChimeStartMinute", structural: false) }
    }
    var hourlyChimeEndMinute: Int {
        didSet { writer.save(hourlyChimeEndMinute, "clockHourlyChimeEndMinute", structural: false) }
    }
    var worldClocks: [WorldClock] {
        didSet {
            if let data = try? JSONEncoder().encode(worldClocks) { defaults.set(data, forKey: "worldClocks") }
            let oldPinned = oldValue.filter(\.showInMenuBar).map { "\($0.menuBarTag)|\($0.timeZoneID)" }
            let newPinned = worldClocks.filter(\.showInMenuBar).map { "\($0.menuBarTag)|\($0.timeZoneID)" }
            if oldPinned != newPinned {
                NotificationCenter.default.post(name: .vibeCheckSettingsChanged, object: nil)
            }
        }
    }
    /// While the clock panel is open its seconds tick even if the menu bar shows minutes only.
    @ObservationIgnored var isPanelOpen = false

    init(defaults: UserDefaults) {
        self.defaults = defaults
        writer = SettingsWriter(defaults: defaults)
        format = defaults.string(forKey: "clockFormat").flatMap(ClockFormat.init(rawValue:)) ?? .dayTime
        customFormat = defaults.string(forKey: "clockCustomFormat") ?? "EEE d MMM HH:mm"
        showSeconds = defaults.bool(forKey: "clockShowSeconds")
        showWeekNumberInMenuBar = defaults.bool(forKey: "clockShowWeekNumberInMenuBar")
        showWeekNumbersInCalendar = defaults.bool(forKey: "clockShowWeekNumbersInCalendar")
        calendarIconStyle = defaults.string(forKey: "clockCalendarIconStyle").flatMap(CalendarIconStyle.init(rawValue:)) ?? .day
        let savedPanelH = defaults.double(forKey: "clockPanelHeight")
        panelHeight = savedPanelH > 0 ? min(max(savedPanelH, 260), 1400) : 0
        showCalendarEvents = defaults.bool(forKey: "clockShowCalendarEvents")
        let savedDays = defaults.integer(forKey: "clockCalendarDaysAhead")
        calendarDaysAhead = [1, 3, 7, 14].contains(savedDays) ? savedDays : 7
        showAllDayEvents = defaults.object(forKey: "clockShowAllDayEvents") as? Bool ?? true
        hidePastEventsToday = defaults.bool(forKey: "clockHidePastEventsToday")
        showRemindersInAgenda = defaults.bool(forKey: "clockShowRemindersInAgenda")
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: "clockHiddenCalendarIDs") ?? [])
        nextEventInMenuBar = defaults.bool(forKey: "clockNextEventInMenuBar")
        nextEventShowTitle = defaults.object(forKey: "clockNextEventShowTitle") as? Bool ?? true
        nextEventOnlyVideoCalls = defaults.bool(forKey: "clockNextEventOnlyVideoCalls")
        nextEventShowDuringEntireEvent = defaults.object(forKey: "clockNextEventShowDuringEntireEvent") as? Bool ?? true
        nextEventClickToJoin = defaults.bool(forKey: "clockNextEventClickToJoin")
        nextEventShowJoinButton = defaults.object(forKey: "clockNextEventShowJoinButton") as? Bool ?? true
        let savedMaxW = defaults.integer(forKey: "clockNextEventMaxWidth")
        nextEventMaxWidth = [120, 160, 200].contains(savedMaxW) ? savedMaxW : 160
        let savedLookahead = defaults.integer(forKey: "clockNextEventLookaheadHours")
        nextEventLookaheadHours = [1, 2, 4, 8, 24].contains(savedLookahead) ? savedLookahead : 4
        meetingAlertStyle = defaults.string(forKey: "clockMeetingAlertStyle").flatMap(MeetingAlertStyle.init(rawValue:)) ?? .off
        let savedLead = defaults.object(forKey: "clockMeetingAlertLeadMinutes") as? Int
        meetingAlertLeadMinutes = savedLead.flatMap { [0, 1, 2, 5].contains($0) ? $0 : nil } ?? 1
        meetingAlertOnlyVideoCalls = defaults.object(forKey: "clockMeetingAlertOnlyVideoCalls") as? Bool ?? true
        meetingAlertOnlyWithAlarm = defaults.bool(forKey: "clockMeetingAlertOnlyWithAlarm")
        meetingAlertSuppressDuringCall = defaults.object(forKey: "clockMeetingAlertSuppressDuringCall") as? Bool ?? true
        meetingAlertPlaySound = defaults.object(forKey: "clockMeetingAlertPlaySound") as? Bool ?? true
        hourlyChimeEnabled = defaults.bool(forKey: "clockHourlyChimeEnabled")
        hourlyChimeCadence = defaults.string(forKey: "clockHourlyChimeCadence").flatMap(ChimeCadence.init(rawValue:)) ?? .hourly
        hourlyChimeSound = defaults.string(forKey: "clockHourlyChimeSound").flatMap(ChimeSound.init(rawValue:)) ?? .tink
        let savedVol = defaults.object(forKey: "clockHourlyChimeVolume") as? Double
        hourlyChimeVolume = savedVol.map { min(max($0, 0.1), 1.0) } ?? 0.5
        hourlyChimeStartMinute = defaults.object(forKey: "clockHourlyChimeStartMinute") as? Int ?? 9 * 60
        hourlyChimeEndMinute = defaults.object(forKey: "clockHourlyChimeEndMinute") as? Int ?? 18 * 60
        worldClocks = defaults.data(forKey: "worldClocks")
            .flatMap { try? JSONDecoder().decode([WorldClock].self, from: $0) } ?? WorldClock.defaults
    }

    var formatStyle: ClockFormatStyle {
        ClockFormatStyle(format: format, seconds: showSeconds, customFormat: customFormat,
                         showWeekNumber: showWeekNumberInMenuBar)
    }

    var menuBarWorldClocks: [WorldClock] {
        Array(worldClocks.filter(\.showInMenuBar).prefix(3))
    }

    /// Width that fits the clock's widest possible text in the current format, so it never jiggles.
    var textWidth: CGFloat {
        let widest = DateComponents(calendar: .current, year: 2026, month: 9, day: 30, hour: 22, minute: 58, second: 58).date ?? Date()
        let text = formatStyle.format(widest)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width) + 2
    }

    /// Fixed width for one pinned menu bar world clock badge (`NYC 22:58`).
    func worldClockWidth(for clock: WorldClock) -> CGFloat {
        let widest = DateComponents(calendar: .current, year: 2026, month: 9, day: 30, hour: 22, minute: 58).date ?? Date()
        let sample = "\(clock.menuBarTag) \(clock.formattedTime(at: widest))"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        return ceil((sample as NSString).size(withAttributes: [.font: font]).width) + 2
    }
}

@Observable
@MainActor
final class WeatherGroup {
    @ObservationIgnored private let defaults: UserDefaults

    var location: WeatherLocation? {
        didSet {
            defaults.set(location.flatMap { try? JSONEncoder().encode($0) }, forKey: "weatherLocation")
            WeatherStore.shared.refresh()
        }
    }
    var unit: TemperatureUnit {
        didSet {
            defaults.set(unit.rawValue, forKey: "temperatureUnit")
            WeatherStore.shared.refresh()
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        location = defaults.data(forKey: "weatherLocation")
            .flatMap { try? JSONDecoder().decode(WeatherLocation.self, from: $0) }
        unit = defaults.string(forKey: "temperatureUnit").flatMap(TemperatureUnit.init(rawValue:))
            ?? (Locale.current.measurementSystem == .us ? .fahrenheit : .celsius)
    }
}

/// The To-do module: which Reminders list it shows ("" = the default list for new reminders).
@Observable
@MainActor
final class TodoGroup {
    @ObservationIgnored private let writer: SettingsWriter

    var listID: String {
        didSet {
            writer.save(listID, "todoListID", structural: false)
            RemindersStore.shared.reload()
        }
    }

    init(defaults: UserDefaults) {
        writer = SettingsWriter(defaults: defaults)
        listID = defaults.string(forKey: "todoListID") ?? ""
    }
}

/// Keep Awake sessions, triggers and schedule, plus the related agent / Bluetooth switches.
@Observable
@MainActor
final class KeepAwakeGroup {
    @ObservationIgnored private let writer: SettingsWriter

    /// Length of a quick-start session in minutes (0 = indefinitely).
    var defaultMinutes: Int {
        didSet { writer.save(defaultMinutes, "keepAwakeDefaultMinutes", structural: false) }
    }
    /// Keep the display on too; off lets the screen sleep while the Mac stays awake.
    var displayOn: Bool {
        didSet { writer.save(displayOn, "keepAwakeDisplayOn", structural: false); KeepAwake.shared.check() }
    }
    /// End a session when on battery below this percent (0 = never).
    var batteryFloor: Int {
        didSet { writer.save(batteryFloor, "keepAwakeBatteryFloor", structural: false); KeepAwake.shared.check() }
    }
    var atLaunch: Bool {
        didSet { writer.save(atLaunch, "keepAwakeAtLaunch", structural: false) }
    }
    /// Time of day for "until" sessions started from Settings, in minutes after midnight.
    var untilMinute: Int {
        didSet { writer.save(untilMinute, "keepAwakeUntilMinute", structural: false) }
    }
    /// Notify when a session ends by itself.
    var notify: Bool {
        didSet { writer.save(notify, "keepAwakeNotify", structural: false) }
    }
    /// Global shortcut (modifier + A) that starts or stops a session.
    var hotkey: Bool {
        didSet { writer.save(hotkey, "keepAwakeHotkey", structural: true) }
    }
    /// Triggers: stay awake automatically while plugged in / while an external display is connected.
    var onPower: Bool {
        didSet { writer.save(onPower, "keepAwakeOnPower", structural: false); KeepAwake.shared.check() }
    }
    var withDisplay: Bool {
        didSet { writer.save(withDisplay, "keepAwakeWithDisplay", structural: false); KeepAwake.shared.check() }
    }
    /// Trigger: stay awake while files are arriving in `downloadsFolderURL` (`DownloadsWatcher`).
    var whileDownloading: Bool {
        didSet {
            writer.save(whileDownloading, "keepAwakeWhileDownloading", structural: false)
            DownloadsWatcher.shared.reset()
            KeepAwake.shared.check()
        }
    }
    /// Trigger: stay awake inside a weekly window (`schedule`).
    var onSchedule: Bool {
        didSet { writer.save(onSchedule, "keepAwakeOnSchedule", structural: false); KeepAwake.shared.check() }
    }
    /// Trigger: stay awake while an AI agent writes to its logs (`AgentWatch`).
    var whileAgentWorks: Bool {
        didSet {
            writer.save(whileAgentWorks, "keepAwakeWhileAgentWorks", structural: false)
            AgentUsageStore.shared.refresh()
            KeepAwake.shared.check()
        }
    }
    /// Trigger: stay awake while connected to the Wi-Fi network named in `wifiName`.
    /// Asks for Location permission when switched on (macOS hides network names without it).
    var whileOnWiFi: Bool {
        didSet {
            writer.save(whileOnWiFi, "keepAwakeWhileOnWiFi", structural: false)
            if whileOnWiFi { WiFiTrigger.shared.requestAccess() }
            KeepAwake.shared.check()
        }
    }
    var wifiName: String {
        didSet { writer.save(wifiName, "keepAwakeWiFiName", structural: false); KeepAwake.shared.check() }
    }
    /// Notify when an agent finishes a run of 10 minutes or more.
    var notifyAgentFinished: Bool {
        didSet { writer.save(notifyAgentFinished, "notifyAgentFinished", structural: false); AgentUsageStore.shared.refresh() }
    }
    var scheduleDays: Int {
        didSet { writer.save(scheduleDays, "keepAwakeScheduleDays", structural: false); KeepAwake.shared.check() }
    }
    var scheduleStart: Int {
        didSet { writer.save(scheduleStart, "keepAwakeScheduleStart", structural: false); KeepAwake.shared.check() }
    }
    var scheduleEnd: Int {
        didSet { writer.save(scheduleEnd, "keepAwakeScheduleEnd", structural: false); KeepAwake.shared.check() }
    }
    var schedule: AwakeSchedule {
        AwakeSchedule(days: scheduleDays, startMinute: scheduleStart, endMinute: scheduleEnd)
    }
    /// Folder the downloads trigger watches; empty means the user's Downloads folder.
    var downloadsFolder: String {
        didSet {
            writer.save(downloadsFolder, "keepAwakeDownloadsFolder", structural: false)
            DownloadsWatcher.shared.reset()
            KeepAwake.shared.check()
        }
    }
    var downloadsFolderURL: URL {
        downloadsFolder.isEmpty ? DownloadsWatcher.defaultFolder
            : URL(fileURLWithPath: downloadsFolder, isDirectory: true)
    }
    /// Turn Bluetooth off while the Mac sleeps, back on at wake (`BluetoothSnooze`).
    var bluetoothOffWhileAsleep: Bool {
        didSet {
            writer.save(bluetoothOffWhileAsleep, "bluetoothOffWhileAsleep", structural: false)
            if bluetoothOffWhileAsleep { BluetoothSnooze.shared.requestAccess() }
        }
    }
    /// Show a cup in the menu bar while a session runs.
    var showInMenuBar: Bool {
        didSet { writer.save(showInMenuBar, "keepAwakeShowInMenuBar", structural: true) }
    }
    /// A standalone Keep Awake item in the menu bar (always visible). Click toggles, right-click shows a menu.
    var menuBarItem: Bool {
        didSet { writer.save(menuBarItem, "keepAwakeMenuBarItem", structural: true) }
    }

    init(defaults: UserDefaults) {
        writer = SettingsWriter(defaults: defaults)
        defaultMinutes = defaults.object(forKey: "keepAwakeDefaultMinutes") as? Int ?? 0
        displayOn = defaults.object(forKey: "keepAwakeDisplayOn") as? Bool ?? true
        batteryFloor = defaults.object(forKey: "keepAwakeBatteryFloor") as? Int ?? 10
        atLaunch = defaults.bool(forKey: "keepAwakeAtLaunch")
        showInMenuBar = defaults.object(forKey: "keepAwakeShowInMenuBar") as? Bool ?? true
        menuBarItem = defaults.bool(forKey: "keepAwakeMenuBarItem")
        untilMinute = defaults.object(forKey: "keepAwakeUntilMinute") as? Int ?? 18 * 60
        notify = defaults.object(forKey: "keepAwakeNotify") as? Bool ?? true
        hotkey = defaults.object(forKey: "keepAwakeHotkey") as? Bool ?? true
        onPower = defaults.bool(forKey: "keepAwakeOnPower")
        withDisplay = defaults.bool(forKey: "keepAwakeWithDisplay")
        whileDownloading = defaults.bool(forKey: "keepAwakeWhileDownloading")
        downloadsFolder = defaults.string(forKey: "keepAwakeDownloadsFolder") ?? ""
        onSchedule = defaults.bool(forKey: "keepAwakeOnSchedule")
        whileAgentWorks = defaults.bool(forKey: "keepAwakeWhileAgentWorks")
        notifyAgentFinished = defaults.bool(forKey: "notifyAgentFinished")
        whileOnWiFi = defaults.bool(forKey: "keepAwakeWhileOnWiFi")
        wifiName = defaults.string(forKey: "keepAwakeWiFiName") ?? ""
        scheduleDays = defaults.object(forKey: "keepAwakeScheduleDays") as? Int ?? AwakeSchedule.weekdays
        scheduleStart = defaults.object(forKey: "keepAwakeScheduleStart") as? Int ?? 9 * 60
        scheduleEnd = defaults.object(forKey: "keepAwakeScheduleEnd") as? Int ?? 17 * 60
        bluetoothOffWhileAsleep = defaults.bool(forKey: "bluetoothOffWhileAsleep")
    }
}
