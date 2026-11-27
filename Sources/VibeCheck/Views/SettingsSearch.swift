import AppKit
import CoreLocation
import EventKit
import SwiftUI

/// Sub-tabs inside the Date & Time module page so its 6 sections stay calm and scannable.
enum ClockSettingsTab: String, CaseIterable, Identifiable {
    case clock, calendar, chime
    var id: String { rawValue }
    var title: String {
        switch self {
        case .clock: String(localized: "Clock & World")
        case .calendar: String(localized: "Calendar & Calls")
        case .chime: String(localized: "Hourly Chime")
        }
    }
}

/// One searchable control in Settings, with everything needed to jump straight to it,
/// expand any enclosing disclosure group, switch sub-tabs, and highlight the row.
struct SettingsSearchEntry: Identifiable, Hashable {
    let id: String
    let section: SettingsSection
    let title: String
    let breadcrumb: String
    let keywords: String
    var disclosureID: String? = nil
    var clockTab: ClockSettingsTab? = nil

    func matches(_ query: String) -> Bool {
        let words = query.split(separator: " ")
        guard !words.isEmpty else { return false }
        let haystack = "\(title) \(breadcrumb) \(keywords) \(section.title)"
        return words.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
    }
}

/// Curated index of individual settings controls and synonyms for Spotlight-style search.
enum SettingsSearchIndex {
    static let entries: [SettingsSearchEntry] = {
        var list: [SettingsSearchEntry] = [
            // General
            SettingsSearchEntry(id: "general.launchAtLogin", section: .general,
                                title: String(localized: "Launch at login"),
                                breadcrumb: String(localized: "General › Startup"),
                                keywords: "startup boot login open automatically"),
            SettingsSearchEntry(id: "general.quickToggles", section: .general,
                                title: String(localized: "Quick toggles & summary card"),
                                breadcrumb: String(localized: "General › Deck"),
                                keywords: "deck mic mute bluetooth volume brightness share vibe card summary"),
            SettingsSearchEntry(id: "general.deckOpacity", section: .general,
                                title: String(localized: "Popover opacity"),
                                breadcrumb: String(localized: "General › Deck"),
                                keywords: "glass blur transparency background solid dark light appearance translucent"),
            SettingsSearchEntry(id: "general.permissions", section: .general,
                                title: String(localized: "Permissions & Privacy"),
                                breadcrumb: String(localized: "General › Privacy"),
                                keywords: "calendar reminders location bluetooth accessibility pasteboard privacy tcc access"),
            SettingsSearchEntry(id: "general.explanations", section: .general,
                                title: String(localized: "On-device explanations"),
                                breadcrumb: String(localized: "General"),
                                keywords: "ai explain apple intelligence foundation models local"),
            SettingsSearchEntry(id: "general.refreshInterval", section: .general,
                                title: String(localized: "Update interval"),
                                breadcrumb: String(localized: "General › Advanced"),
                                keywords: "sampling refresh rate polling seconds cpu usage",
                                disclosureID: "general.advanced"),
            SettingsSearchEntry(id: "general.backup", section: .general,
                                title: String(localized: "Export, import & reset settings"),
                                breadcrumb: String(localized: "General › Backup & Reset"),
                                keywords: "backup export import plist restore defaults factory reset"),

            // Menu Bar
            SettingsSearchEntry(id: "menuBar.style", section: .menuBar,
                                title: String(localized: "Menu bar style"),
                                breadcrumb: String(localized: "Menu Bar › Style"),
                                keywords: "ring separate combined one item appearance layout"),
            SettingsSearchEntry(id: "menuBar.ring", section: .menuBar,
                                title: String(localized: "Vibe ring & agent pulse"),
                                breadcrumb: String(localized: "Menu Bar › Style"),
                                keywords: "vibe ring color always monochrome pulse hooks needs input"),
            SettingsSearchEntry(id: "menuBar.spacing", section: .menuBar,
                                title: String(localized: "Item spacing & colorful graphs"),
                                breadcrumb: String(localized: "Menu Bar › Advanced"),
                                keywords: "compact tight normal padding colorful monochrome graphs",
                                disclosureID: "menuBar.advanced"),
            SettingsSearchEntry(id: "menuBar.notch", section: .menuBar,
                                title: String(localized: "Fit around the camera notch"),
                                breadcrumb: String(localized: "Menu Bar › Advanced"),
                                keywords: "notch macbook camera overflow badge +n hide",
                                disclosureID: "menuBar.advanced"),
            SettingsSearchEntry(id: "menuBar.items", section: .menuBar,
                                title: String(localized: "Menu bar items & order"),
                                breadcrumb: String(localized: "Menu Bar › Items"),
                                keywords: "reorder drag sort enable disable modules show hide"),

            // Keep Awake
            SettingsSearchEntry(id: "keepAwake.session", section: .keepAwake,
                                title: String(localized: "Default keep-awake session"),
                                breadcrumb: String(localized: "Keep Awake"),
                                keywords: "caffeinate sleep timer indefinitely duration until"),
            SettingsSearchEntry(id: "keepAwake.power", section: .keepAwake,
                                title: String(localized: "Keep awake on power, display, Wi-Fi or schedule"),
                                breadcrumb: String(localized: "Keep Awake › Power & Hardware"),
                                keywords: "plugged in charger external monitor wifi ssid network schedule days hours"),
            SettingsSearchEntry(id: "keepAwake.work", section: .keepAwake,
                                title: String(localized: "Keep awake for AI agents, calls & downloads"),
                                breadcrumb: String(localized: "Keep Awake › Work & Activity"),
                                keywords: "agent claude codex call guard camera mic zoom downloads folder"),
            SettingsSearchEntry(id: "keepAwake.behavior", section: .keepAwake,
                                title: String(localized: "Display sleep & battery floor"),
                                breadcrumb: String(localized: "Keep Awake › Sleep & Display"),
                                keywords: "screen lid display battery floor stop below cup launch"),
            SettingsSearchEntry(id: "keepAwake.bluetooth", section: .keepAwake,
                                title: String(localized: "Turn Bluetooth off while the Mac sleeps"),
                                breadcrumb: String(localized: "Keep Awake › Sleep & Display"),
                                keywords: "bluetooth headphones airpods snooze sleep wake"),

            // Alerts
            SettingsSearchEntry(id: "alerts.rules", section: .alerts,
                                title: String(localized: "Threshold alert rules"),
                                breadcrumb: String(localized: "Alerts"),
                                keywords: "notifications warnings cpu temperature memory battery disk threshold"),
            SettingsSearchEntry(id: "alerts.smart", section: .alerts,
                                title: String(localized: "Smart & activity alerts"),
                                breadcrumb: String(localized: "Alerts › Smart Alerts"),
                                keywords: "memory leak throttling slow charger agent finished run 10 minutes"),
            SettingsSearchEntry(id: "alerts.advanced", section: .alerts,
                                title: String(localized: "Restore default alerts & test notification"),
                                breadcrumb: String(localized: "Alerts › Advanced"),
                                keywords: "test notification send restore defaults",
                                disclosureID: "alerts.advanced"),

            // Clipboard
            SettingsSearchEntry(id: "clipboard.enabled", section: .clipboard,
                                title: String(localized: "Keep clipboard history"),
                                breadcrumb: String(localized: "Clipboard"),
                                keywords: "copy paste history limit restarts clear pasteboard"),
            SettingsSearchEntry(id: "clipboard.ignored", section: .clipboard,
                                title: String(localized: "Ignored apps"),
                                breadcrumb: String(localized: "Clipboard › Privacy"),
                                keywords: "never record password manager 1password bitwarden exclude"),
            SettingsSearchEntry(id: "clipboard.snippets", section: .clipboard,
                                title: String(localized: "Pinned snippets"),
                                breadcrumb: String(localized: "Clipboard"),
                                keywords: "snippets templates quick paste pin"),

            // Shortcuts
            SettingsSearchEntry(id: "shortcuts.global", section: .shortcuts,
                                title: String(localized: "Global keyboard shortcuts"),
                                breadcrumb: String(localized: "Shortcuts"),
                                keywords: "hotkeys modifier secure input clipboard cursor join call keep awake"),
            SettingsSearchEntry(id: "shortcuts.modules", section: .shortcuts,
                                title: String(localized: "Module shortcuts (1–9, 0)"),
                                breadcrumb: String(localized: "Shortcuts › Advanced"),
                                keywords: "module keys numbers open panel",
                                disclosureID: "shortcuts.modules"),

            // Date & Time sub-tabs
            SettingsSearchEntry(id: "clock.format", section: .module(.clock),
                                title: String(localized: "Clock format, seconds & week numbers"),
                                breadcrumb: String(localized: "Date & Time › Clock & World"),
                                keywords: "time format custom pattern seconds week number calendar icon",
                                clockTab: .clock),
            SettingsSearchEntry(id: "clock.world", section: .module(.clock),
                                title: String(localized: "World clocks"),
                                breadcrumb: String(localized: "Date & Time › Clock & World"),
                                keywords: "timezone city utc ist tokyo london pin menu bar",
                                clockTab: .clock),
            SettingsSearchEntry(id: "clock.calendar", section: .module(.clock),
                                title: String(localized: "Calendar events & upcoming menu bar item"),
                                breadcrumb: String(localized: "Date & Time › Calendar & Calls"),
                                keywords: "calendar eventkit reminders agenda next event upcoming join video call zoom meet teams",
                                clockTab: .calendar),
            SettingsSearchEntry(id: "clock.meetingAlerts", section: .module(.clock),
                                title: String(localized: "Meeting notifications & fullscreen alert"),
                                breadcrumb: String(localized: "Date & Time › Calendar & Calls"),
                                keywords: "meeting alert fullscreen banner snooze sound call",
                                clockTab: .calendar),
            SettingsSearchEntry(id: "clock.chime", section: .module(.clock),
                                title: String(localized: "Hourly chime"),
                                breadcrumb: String(localized: "Date & Time › Hourly Chime"),
                                keywords: "chime sound bell hour half quarter volume active hours",
                                clockTab: .chime),

            // Agents & other specialized module controls
            SettingsSearchEntry(id: "agents.sources", section: .module(.agents),
                                title: String(localized: "AI agent sources & Claude account"),
                                breadcrumb: String(localized: "Agents"),
                                keywords: "claude codex opencode copilot antigravity agy profile folder account"),
            SettingsSearchEntry(id: "agents.limits", section: .module(.agents),
                                title: String(localized: "Live Claude & Antigravity plan limits"),
                                breadcrumb: String(localized: "Agents › Plan Limits"),
                                keywords: "claude antigravity agy plan usage quota 5-hour weekly reset"),
            SettingsSearchEntry(id: "network.publicIP", section: .module(.network),
                                title: String(localized: "Public IP address"),
                                breadcrumb: String(localized: "Network"),
                                keywords: "public ip ipify external address"),
            SettingsSearchEntry(id: "weather.city", section: .module(.weather),
                                title: String(localized: "Weather city & units"),
                                breadcrumb: String(localized: "Weather"),
                                keywords: "forecast city celsius fahrenheit open-meteo"),
            SettingsSearchEntry(id: "todo.list", section: .module(.todo),
                                title: String(localized: "Apple Reminders list"),
                                breadcrumb: String(localized: "To-do"),
                                keywords: "reminders tasks icloud list checklist"),

            // About & Support
            SettingsSearchEntry(id: "about.updates", section: .about,
                                title: String(localized: "Check for updates"),
                                breadcrumb: String(localized: "About VibeCheck › Updates"),
                                keywords: "version release brew upgrade terminal update"),
            SettingsSearchEntry(id: "about.support", section: .about,
                                title: String(localized: "Support VibeCheck"),
                                breadcrumb: String(localized: "About VibeCheck › Support"),
                                keywords: "buy me a coffee donate tip sponsor github star thanks"),
        ]
        // Ensure every hardware/extra module is directly findable too.
        for module in Module.allCases {
            list.append(SettingsSearchEntry(
                id: "module.\(module.rawValue).hero",
                section: .module(module),
                title: module.title,
                breadcrumb: module.isExtra ? String(localized: "Extras") : String(localized: "Monitors"),
                keywords: "\(module.settingsKeywords) \(module.settingsSummary)"
            ))
        }
        return list
    }()

    static func search(_ query: String) -> [SettingsSearchEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let hits = entries.filter { $0.matches(trimmed) }
        // Prioritize title matches over keyword-only matches.
        return hits.sorted { lhs, rhs in
            let lTitle = lhs.title.localizedCaseInsensitiveContains(trimmed)
            let rTitle = rhs.title.localizedCaseInsensitiveContains(trimmed)
            if lTitle != rTitle { return lTitle }
            return false
        }
    }
}

/// Shared Settings navigation, persistence, deep-search reveal, and disclosure state.
@Observable
@MainActor
final class SettingsRouter {
    static let shared = SettingsRouter()
    private static let lastSectionKey = "settings.lastSection"
    @ObservationIgnored private let defaults: UserDefaults

    var section: SettingsSection? {
        didSet {
            if let id = section?.id {
                defaults.set(id, forKey: Self.lastSectionKey)
            }
        }
    }
    var clockTab: ClockSettingsTab = .clock
    /// Sidebar search text; cleared by `open` so the page you jump to is visible in the list.
    var query = ""
    /// Currently spotlight-highlighted control anchor ID, cleared automatically after a brief pulse.
    var highlightedControlID: String?
    /// Disclosure groups expanded programmatically (or by the user).
    var expandedDisclosures: Set<String> = []
    /// Bumped on ⌘F to focus the sidebar search field.
    var searchFocusToken = 0
    @ObservationIgnored private var clearHighlightTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.lastSectionKey)
        section = saved.flatMap(SettingsSection.from(id:)) ?? .menuBar
    }

    func open(_ section: SettingsSection) {
        query = ""
        self.section = section
    }

    /// Navigates to a control from deep search, expanding any enclosing disclosure and pulsing the row.
    func reveal(_ entry: SettingsSearchEntry) {
        section = entry.section
        if let tab = entry.clockTab { clockTab = tab }
        if let disclosureID = entry.disclosureID {
            expandedDisclosures.insert(disclosureID)
        }
        highlightedControlID = entry.id
        clearHighlightTask?.cancel()
        clearHighlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.1))
            guard !Task.isCancelled else { return }
            if self?.highlightedControlID == entry.id {
                withAnimation(.easeOut(duration: 0.35)) {
                    self?.highlightedControlID = nil
                }
            }
        }
    }

    func isExpanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { self.expandedDisclosures.contains(id) },
            set: { on in
                if on { self.expandedDisclosures.insert(id) }
                else { self.expandedDisclosures.remove(id) }
            }
        )
    }
}

/// Subtle spotlight pulse drawn cleanly inside a setting row jumped to via Search (unclipped in grouped Forms).
private struct SpotlightHighlightModifier: ViewModifier {
    let anchorID: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var isHighlighted: Bool { SettingsRouter.shared.highlightedControlID == anchorID }

    func body(content: Content) -> some View {
        content
            .id(anchorID)
            .padding(.horizontal, isHighlighted ? 6 : 0)
            .padding(.vertical, isHighlighted ? 3 : 0)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(isHighlighted ? (contrast == .increased ? 0.24 : 0.16) : 0))
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isHighlighted ? (contrast == .increased ? 0.9 : 0.65) : 0),
                                  lineWidth: contrast == .increased ? 1.5 : 1)
                    .allowsHitTesting(false)
            )
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.78),
                       value: isHighlighted)
    }
}

extension View {
    /// Marks a Settings row or section so Spotlight search can scroll to and highlight it.
    func settingsAnchor(_ id: String) -> some View {
        modifier(SpotlightHighlightModifier(anchorID: id))
    }
}

// MARK: - Unified Permissions Inspector

enum PermissionState: Equatable {
    case allowed, needsAttention, notRequested, unavailable

    var label: String {
        switch self {
        case .allowed: String(localized: "Allowed")
        case .needsAttention: String(localized: "Action Needed")
        case .notRequested: String(localized: "Not Requested")
        case .unavailable: String(localized: "Unavailable")
        }
    }

    var color: Color {
        switch self {
        case .allowed: .green
        case .needsAttention: .orange
        case .notRequested: .secondary
        case .unavailable: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .allowed: "checkmark.circle.fill"
        case .needsAttention: "exclamationmark.triangle.fill"
        case .notRequested: "circle.dashed"
        case .unavailable: "minus.circle"
        }
    }
}

struct PermissionItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let color: Color
    let purpose: String
    let state: PermissionState
    let settingsURL: URL?
}

/// Passively inspects VibeCheck's macOS TCC permissions without triggering any system prompts.
@MainActor
enum PermissionsInspector {
    static func snapshot() -> [PermissionItem] {
        var items: [PermissionItem] = []

        // Calendar
        let calStatus = EKEventStore.authorizationStatus(for: .event)
        let calState: PermissionState = switch calStatus {
        case .fullAccess, .authorized: .allowed
        case .notDetermined: .notRequested
        default: .needsAttention
        }
        items.append(PermissionItem(
            id: "calendar",
            title: String(localized: "Calendar"),
            symbol: "calendar",
            color: .red,
            purpose: String(localized: "Agenda, upcoming menu bar event, and meeting alerts."),
            state: calState,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        ))

        // Reminders
        let remStatus = EKEventStore.authorizationStatus(for: .reminder)
        let remState: PermissionState = switch remStatus {
        case .fullAccess, .authorized: .allowed
        case .notDetermined: .notRequested
        default: .needsAttention
        }
        items.append(PermissionItem(
            id: "reminders",
            title: String(localized: "Reminders"),
            symbol: "checklist",
            color: .orange,
            purpose: String(localized: "To-do module synced with Apple Reminders."),
            state: remState,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
        ))

        // Bluetooth
        let btState: PermissionState = if !BluetoothSnooze.shared.isAvailable {
            .unavailable
        } else {
            switch BluetoothSnooze.shared.access {
            case .allowed: .allowed
            case .notAsked: .notRequested
            case .denied: .needsAttention
            }
        }
        items.append(PermissionItem(
            id: "bluetooth",
            title: String(localized: "Bluetooth"),
            symbol: "dot.radiowaves.left.and.right",
            color: .blue,
            purpose: String(localized: "Quick Bluetooth toggle and turning Bluetooth off while sleeping."),
            state: btState,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
        ))

        // Location (for Wi-Fi SSID)
        let locState: PermissionState = if WiFiTrigger.shared.authorized {
            .allowed
        } else if WiFiTrigger.shared.denied {
            .needsAttention
        } else {
            .notRequested
        }
        items.append(PermissionItem(
            id: "location",
            title: String(localized: "Location Services"),
            symbol: "wifi",
            color: .teal,
            purpose: String(localized: "Required by macOS to read your Wi-Fi network name for Keep Awake triggers."),
            state: locState,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
        ))

        // Accessibility (auto-paste / keyboard cleaner)
        let axTrusted = AXIsProcessTrusted()
        items.append(PermissionItem(
            id: "accessibility",
            title: String(localized: "Accessibility"),
            symbol: "figure.stand",
            color: .indigo,
            purpose: String(localized: "Auto-pasting clipboard entries into the frontmost app and Keyboard Cleaner."),
            state: axTrusted ? .allowed : .notRequested,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        ))

        // Pasteboard (macOS 15.4+)
        if #available(macOS 15.4, *) {
            let pbState: PermissionState = switch NSPasteboard.general.accessBehavior {
            case .alwaysAllow: .allowed
            case .alwaysDeny: .needsAttention
            default: .notRequested
            }
            items.append(PermissionItem(
                id: "pasteboard",
                title: String(localized: "Paste from Other Apps"),
                symbol: "doc.on.clipboard",
                color: .purple,
                purpose: String(localized: "Background clipboard history without repeated confirmation prompts."),
                state: pbState,
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security")
            ))
        }

        return items
    }

    static func attentionCount(in items: [PermissionItem]) -> Int {
        items.filter { $0.state == .needsAttention }.count
    }
}

/// Sheet presenting every system permission VibeCheck can use, with live status and one-click Privacy deep links.
struct PermissionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PermissionItem] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SettingsIcon(symbol: "hand.raised.fill", color: .blue, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Permissions & Privacy")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Text("Everything stays on your Mac. VibeCheck only asks when you turn a feature on.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            Form {
                Section {
                    ForEach(items) { item in
                        HStack(alignment: .center, spacing: 12) {
                            SettingsIcon(symbol: item.symbol, color: item.color, size: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).fontWeight(.medium)
                                Text(item.purpose)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 12)
                            Label(item.state.label, systemImage: item.state.symbol)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(item.state.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(item.state.color.opacity(0.12)))
                            if let url = item.settingsURL, item.state != .unavailable {
                                Button("Open…") { NSWorkspace.shared.open(url) }
                                    .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Refresh Status") { items = PermissionsInspector.snapshot() }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 560, height: 470)
        .onAppear { items = PermissionsInspector.snapshot() }
    }
}
