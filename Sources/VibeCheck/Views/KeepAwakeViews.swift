import SwiftUI

/// Items shared by the deck's cup menu and Settings: start for a length, while an app runs, or stop.
struct AwakeMenuItems: View {
    @Environment(AppSettings.self) private var settings
    private var awake: KeepAwake { .shared }

    var body: some View {
        @Bindable var settings = settings
        if let session = awake.session {
            Text(session.focus ? "Focusing, \(session.remaining(now: Date()))" : "Awake \(session.remaining(now: Date()))")
            Button(session.focus ? "End Focus Session" : "Stop Keeping Awake") { awake.stop() }
            Divider()
        }
        Section("Focus") {
            ForEach(FocusPreset.minutes, id: \.self) { minutes in
                Button("Focus for \(minutes) Minutes") { awake.startFocus(minutes: minutes) }
            }
        }
        Section(awake.isActive ? "Start Over" : "Keep Awake") {
            ForEach(AwakePreset.minutes, id: \.self) { minutes in
                Button(AwakePreset.title(minutes)) { awake.start(minutes: minutes) }
            }
            Menu("Until") {
                ForEach(AwakePreset.upcomingHours(), id: \.self) { date in
                    Button(date.formatted(date: .omitted, time: .shortened)) { awake.start(.at(date)) }
                }
                Divider()
                Button("Choose a Time…") { (NSApp.delegate as? AppDelegate)?.showSettings(.keepAwake) }
            }
            Menu("While an App Is Running") {
                let apps = KeepAwake.runningApps()
                if apps.isEmpty { Text("No apps running") }
                ForEach(apps, id: \.bundleID) { app in
                    Button(app.name) { awake.start(.whileRunning(bundleID: app.bundleID, name: app.name)) }
                }
            }
        }
        Divider()
        Toggle("Keep the Display On", isOn: $settings.keepAwakeDisplayOn)
    }
}

/// Cup button in the deck header; filled while a session runs.
struct AwakeMenuButton: View {
    @State private var hovering = false
    private var awake: KeepAwake { .shared }

    var body: some View {
        let help = awake.isActive ? "Keeping your Mac awake" : "Keep your Mac awake"
        Menu {
            AwakeMenuItems()
        } label: {
            Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.quaternary.opacity(hovering ? 1 : 0)))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(awake.isActive ? Color.accentColor : .secondary)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering } }
    }
}

// MARK: - Settings

struct KeepAwakeSettings: View {
    @Environment(AppSettings.self) private var settings
    private var awake: KeepAwake { .shared }

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                LabeledContent {
                    if awake.isActive {
                        Button("Stop") { awake.stop() }
                    } else {
                        Button("Start") { awake.start(minutes: settings.keepAwakeDefaultMinutes) }
                    }
                } label: {
                    TimelineView(.periodic(from: .now, by: 15)) { context in Text(status(context.date)) }
                    if let reason = awake.lastEndReason, !awake.isActive {
                        Text("Last session ended: \(reason.message)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("Start sessions for", selection: $settings.keepAwakeDefaultMinutes) {
                    ForEach(AwakePreset.minutes, id: \.self) { Text(AwakePreset.title($0)).tag($0) }
                }
                LabeledContent("Or stay awake until") {
                    HStack {
                        DatePicker("Time", selection: untilTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Button("Start") {
                            awake.start(.at(AwakePreset.nextOccurrence(ofMinute: settings.keepAwakeUntilMinute)))
                        }
                    }
                }
            } footer: {
                Text("The cup in the deck has more choices, like staying awake while an app is running. A time that has already passed today means tomorrow.")
                    .settingsFooter()
            }
            Section("Automatically keep awake") {
                Toggle("While plugged in", isOn: $settings.keepAwakeOnPower)
                Toggle("While an external display is connected", isOn: $settings.keepAwakeWithDisplay)
                Toggle(isOn: $settings.keepAwakeWhileDownloading) {
                    Text("While files are downloading")
                    Text("Watches \(settings.downloadsFolderURL.lastPathComponent) for files that are still arriving.")
                }
                Toggle("On a schedule", isOn: $settings.keepAwakeOnSchedule)
                if settings.keepAwakeOnSchedule {
                    LabeledContent("Days") { ScheduleDaysPicker(days: $settings.keepAwakeScheduleDays) }
                    LabeledContent("Hours") {
                        HStack {
                            DatePicker("From", selection: minuteBinding(\.keepAwakeScheduleStart),
                                       displayedComponents: .hourAndMinute).labelsHidden()
                            Text("to")
                            DatePicker("To", selection: minuteBinding(\.keepAwakeScheduleEnd),
                                       displayedComponents: .hourAndMinute).labelsHidden()
                        }
                    }
                }
                if settings.keepAwakeWhileDownloading {
                    LabeledContent("Folder") {
                        HStack {
                            Text(settings.downloadsFolderURL.path(percentEncoded: false)
                                    .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            Button("Choose…") { chooseDownloadsFolder() }
                            if !settings.keepAwakeDownloadsFolder.isEmpty {
                                Button("Reset") { settings.keepAwakeDownloadsFolder = "" }
                            }
                        }
                    }
                }
            }
            Section {
                Toggle("Keep the display on", isOn: $settings.keepAwakeDisplayOn)
                Picker("On battery, stop below", selection: $settings.keepAwakeBatteryFloor) {
                    Text("Never").tag(0)
                    ForEach([10, 20, 30, 50], id: \.self) { Text("\($0)%").tag($0) }
                }
                Toggle("Start a session when VibeCheck opens", isOn: $settings.keepAwakeAtLaunch)
                Toggle("Notify me when a session ends by itself", isOn: $settings.keepAwakeNotify)
                Toggle("\(settings.hotkeyModifier.symbols)A starts or stops a session", isOn: $settings.keepAwakeHotkey)
                    .disabled(!settings.hotkeysEnabled)
                Toggle(isOn: $settings.keepAwakeMenuBarItem) {
                    Text("Keep Awake item in the menu bar")
                    Text("Always shown. Click it to start or stop, using the length in “Start sessions for” above. Right-click (or ⌥-click) for every option.")
                }
                Toggle("Show a cup in the menu bar while awake", isOn: $settings.keepAwakeShowInMenuBar)
                    .disabled(settings.keepAwakeMenuBarItem)
            } footer: {
                Text("With the display allowed to sleep, the screen turns off but downloads, builds and music keep going. Closing the lid still puts the Mac to sleep.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
    }

    /// A stored minute-of-day setting as a Date for a time picker.
    private func minuteBinding(_ key: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: settings[keyPath: key] / 60, minute: settings[keyPath: key] % 60,
                                  second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            settings[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    /// The stored minute-of-day as a Date for the time picker.
    private var untilTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: settings.keepAwakeUntilMinute / 60, minute: settings.keepAwakeUntilMinute % 60,
                                  second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            settings.keepAwakeUntilMinute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private func chooseDownloadsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.downloadsFolderURL
        panel.prompt = "Watch"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.keepAwakeDownloadsFolder = url == DownloadsWatcher.defaultFolder ? "" : url.path(percentEncoded: false)
    }

    private func status(_ now: Date) -> String {
        guard let session = awake.session else { return "Your Mac sleeps as usual" }
        return "Staying awake \(session.remaining(now: now))"
    }
}

/// Seven day buttons in the user's week order (Monday first where that's the custom), stored as weekday bits.
private struct ScheduleDaysPicker: View {
    @Binding var days: Int

    var body: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 4) {
            ForEach(order, id: \.self) { weekday in
                let on = days & (1 << weekday) != 0
                Button(symbols[weekday - 1]) { days ^= 1 << weekday }
                    .buttonStyle(.bordered)
                    .tint(on ? .accentColor : nil)
                    .background(on ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.25)) : nil)
                    .controlSize(.small)
                    .accessibilityLabel(calendar.standaloneWeekdaySymbols[weekday - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
