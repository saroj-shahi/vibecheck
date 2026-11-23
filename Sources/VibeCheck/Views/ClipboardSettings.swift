import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Clipboard: history on/off, length, keep across restarts, ignored apps, clear, snippets.
struct ClipboardSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var newSnippet = ""
    private let clip = ClipboardHistory.shared

    var body: some View {
        @Bindable var clip = clip
        Form {
            Section {
                Toggle("Keep clipboard history", isOn: $clip.isEnabled)
                if clip.isEnabled, let warning = accessWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Open Privacy & Security") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
                    }
                }
                Stepper("Remember the last \(clip.limit) items", value: $clip.limit, in: 10...200, step: 10)
                    .disabled(!clip.isEnabled)
                Toggle("Keep history across restarts", isOn: $clip.keepAcrossRestarts)
                    .disabled(!clip.isEnabled)
                Button("Clear History", role: .destructive) { clip.clear() }
                    .disabled(clip.items.isEmpty)
            } footer: {
                Text("Off by default. Find copies in ⌘K: type “clip”. Text up to 64 KB, images up to 5 MB and files are kept, in memory only unless you keep them across restarts (images never are). Never recorded: items apps mark as private, anything copied while secure keyboard entry is on, and copies from the apps below. \(settings.hotkeyModifier.symbols)V can open it from anywhere (see Shortcuts). Pasting into the app you were in needs Accessibility; without it, ↩ copies and you press ⌘V.")
                    .settingsFooter()
            }

            Section {
                // Preset password managers that aren't installed stay on the list, just not shown.
                ForEach(clip.ignoredApps.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }, id: \.self) { bundleID in
                    HStack {
                        Text(Self.appName(bundleID))
                        Spacer()
                        Button { clip.ignoredApps.removeAll { $0 == bundleID } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(Self.appName(bundleID))")
                    }
                }
                Button("Add App…") { addIgnoredApp() }
            } header: {
                Text("Never record copies from")
            } footer: {
                Text("Common password managers are on this list from the start, installed or not.")
                    .settingsFooter()
            }

            Section {
                ForEach(clip.snippets, id: \.self) { snippet in
                    HStack {
                        Text(ClipItem.preview(snippet)).lineLimit(1)
                        Spacer()
                        Button { clip.unpin(snippet) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove snippet")
                    }
                }
                HStack {
                    TextField("New snippet", text: $newSnippet)
                        .onSubmit(addSnippet)
                    Button("Add", action: addSnippet)
                        .disabled(newSnippet.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Pinned snippets")
            } footer: {
                Text("Snippets come first in ⌘K's clipboard results and are kept even with history off. Pin a text copy with ⌘↩ in ⌘K.")
                    .settingsFooter()
            }
        }
        .settingsForm()
    }

    /// What macOS does when VibeCheck reads the clipboard in the background, when it matters.
    private var accessWarning: String? {
        guard #available(macOS 15.4, *) else { return nil }
        return switch NSPasteboard.general.accessBehavior {
        case .alwaysDeny:
            String(localized: "macOS is blocking VibeCheck from reading the clipboard, so nothing is recorded. Allow it in System Settings → Privacy & Security → Paste from Other Apps.")
        case .ask, .default:
            String(localized: "macOS may ask before VibeCheck reads a copy. Choose Always Allow for VibeCheck in System Settings → Privacy & Security → Paste from Other Apps to stop the prompts.")
        default: nil
        }
    }

    private func addSnippet() {
        let text = newSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        clip.pin(text)
        newSnippet = ""
    }

    private func addIgnoredApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier,
              !clip.ignoredApps.contains(id) else { return }
        clip.ignoredApps.append(id)
    }

    private static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
