import AppIntents
import AppKit
import Foundation
import SwiftUI
import VibeCheckShared
import WidgetKit

/// Control Center "Keep Awake" toggle (macOS 26+). The extension is sandboxed and can't hold the power
/// assertion, so it only shows the state the app wrote into the app group and asks the running app (by
/// distributed notification) to start or stop a session.
@available(macOS 26, *)
struct KeepAwakeControl: ControlWidget {
    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        // Off when the app isn't running, whatever the file says (covers a crash while on).
        func currentValue() async throws -> Bool { KeepAwakeApp.isRunning && WidgetShared.readKeepAwake() }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetShared.keepAwakeControlKind, provider: Provider()) { isOn in
            ControlWidgetToggle("Keep Awake", isOn: isOn, action: KeepAwakeIntent()) { on in
                Label(on ? "On" : "Off", systemImage: on ? "cup.and.saucer.fill" : "cup.and.saucer")
            }
        }
        .displayName("Keep Awake")
        .description("Keeps your Mac from sleeping. VibeCheck has to be running.")
    }
}

@available(macOS 26, *)
struct KeepAwakeIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Keep Awake"

    @Parameter(title: "Keep awake")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        // Nobody is listening when VibeCheck isn't running: change nothing, so the control doesn't show a lie.
        guard KeepAwakeApp.isRunning else { return .result() }
        WidgetShared.writeKeepAwake(value)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(value ? WidgetShared.keepAwakeStartName : WidgetShared.keepAwakeStopName),
            object: nil, userInfo: nil, deliverImmediately: true)
        return .result()
    }
}

enum KeepAwakeApp {
    static let bundleID = "io.github.saroj-shahi.vibecheck"
    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
}
