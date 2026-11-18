import SwiftUI

/// Cup button in the deck header; filled while a session runs. Click opens the keep-awake menu; press and
/// hold opens the duration dial (drag toward a length, release to start; release without moving cancels).
struct AwakeMenuButton: View {
    @Environment(DeckModel.self) private var model
    @State private var hovering = false
    @State private var pressed = false
    @State private var holdTask: Task<Void, Never>?
    private var awake: KeepAwake { .shared }

    var body: some View {
        let help = awake.isActive ? "Keeping your Mac awake" : "Keep your Mac awake"
        Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
            .font(.system(size: 12, weight: .medium))
            .frame(width: 26, height: 26)
            .background(Circle().fill(.quaternary.opacity(hovering || pressed ? 1 : 0)))
            .contentShape(Circle())
            .foregroundStyle(awake.isActive ? Color.accentColor : .secondary)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !pressed {
                        pressed = true
                        holdTask = Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            guard !Task.isCancelled else { return }
                            withAnimation(Deck.reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.8)) {
                                model.awakeDialOpen = true
                            }
                        }
                    }
                    if model.awakeDialOpen { model.awakeDialSelection = AwakeDial.segment(for: value.translation) }
                }
                .onEnded { _ in
                    holdTask?.cancel()
                    pressed = false
                    if model.awakeDialOpen {
                        if let index = model.awakeDialSelection { awake.start(minutes: AwakeDial.minutes[index]) }
                        withAnimation(.easeOut(duration: 0.14)) { model.awakeDialOpen = false }
                        model.awakeDialSelection = nil
                    } else {
                        Self.showMenu()
                    }
                })
            .help(help + " (hold for a quick length)")
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(help)
            .accessibilityAction { Self.showMenu() }
            .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering } }
    }

    private static func showMenu() {
        KeepAwakeMenu().build().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// The hold dial's four lengths, by drag direction: up, right, down, left.
enum AwakeDial {
    static let minutes = [15, 60, 240, 0]
    static let labels = ["15m", "1h", "4h", "∞"]

    /// Which length a drag points at; nil inside the 12 pt dead zone (release there cancels).
    static func segment(for translation: CGSize) -> Int? {
        guard hypot(translation.width, translation.height) >= 12 else { return nil }
        let degrees = atan2(translation.width, -translation.height) * 180 / .pi   // 0 = up, clockwise
        return Int(((degrees + 360 + 45).truncatingRemainder(dividingBy: 360)) / 90)
    }
}

/// The dial drawn over the deck while the cup is held: four ring sectors and a center label.
struct AwakeDialView: View {
    let selection: Int?

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                let hot = index == selection
                RingSector(index: index)
                    .fill(hot ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.windowBackground))
                RingSector(index: index).stroke(.separator, lineWidth: 0.5)
                Text(AwakeDial.labels[index])
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(hot ? Color.white : .primary)
                    .offset(x: [0, 56, 0, -56][index], y: [-56, 0, 56, 0][index])
            }
            Circle().fill(.windowBackground).frame(width: 60, height: 60)
                .overlay(Circle().stroke(.separator, lineWidth: 0.5))
            Text(selection.map { AwakeDial.minutes[$0] == 0 ? "Until off" : "Set \(AwakeDial.labels[$0])" } ?? "Drag")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 160, height: 160)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        .accessibilityHidden(true)
    }
}

/// One quarter of the dial's ring (radius 36–76), centred on up / right / down / left.
private struct RingSector: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let mid = Double(index) * 90 - 90                     // SwiftUI angles: 0 = right, so up is −90
        var path = Path()
        path.addArc(center: center, radius: 76, startAngle: .degrees(mid - 43), endAngle: .degrees(mid + 43), clockwise: false)
        path.addArc(center: center, radius: 36, startAngle: .degrees(mid + 43), endAngle: .degrees(mid - 43), clockwise: true)
        path.closeSubpath()
        return path
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
