import AppKit
import SwiftUI

/// Renders the card to an image; works without any window on screen.
@MainActor
enum VibeCardRenderer {
    static let scale: CGFloat = 2

    static func cgImage(_ data: VibeCardData, style: VibeCardStyle) -> CGImage? {
        let renderer = ImageRenderer(content: VibeCardView(data: data, style: style))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(VibeCardView.size)
        return renderer.cgImage
    }

    static func png(_ data: VibeCardData, style: VibeCardStyle) -> Data? {
        guard let image = cgImage(data, style: style) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func defaultFileName(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "VibeCheck-\(f.string(from: date)).png"
    }

    /// A snapshot of the current stats. The culprit decides the apps: CPU when it's the culprit and a process
    /// list exists, otherwise memory (the per-app footprints the verdict already uses).
    static func snapshot(stats: SystemStats, hideNames: Bool) -> VibeCardData {
        var apps: [VibeCardData.App] = []
        var title = String(localized: "Top apps by memory")
        if stats.vibe.culprit == .cpu {
            let top = stats.topApps(by: \.cpu, limit: 3)
            if !top.isEmpty {
                title = String(localized: "Top apps by CPU")
                apps = top.enumerated().map { i, app in
                    .init(id: i, name: app.name, value: "\(Int(app.cpu.rounded()))%", icon: NSRunningApplication(processIdentifier: app.id)?.icon)
                }
            }
        }
        if apps.isEmpty {
            let tracks = stats.appMemoryTracks.compactMap { key, track in track.samples.last.map { (key, track, $0) } }
                .sorted { $0.2.footprint > $1.2.footprint }.prefix(3)
            apps = tracks.enumerated().map { i, t in
                .init(id: i, name: t.1.name, value: Fmt.bytes(t.2.footprint), icon: NSRunningApplication(processIdentifier: t.0.pid)?.icon)
            }
        }
        return VibeCardData.build(vibe: stats.vibe.vibe, verdict: stats.vibe.verdict,
                                  chip: SysctlReader.string("machdep.cpu.brand_string") ?? "Mac",
                                  memoryBytes: ProcessInfo.processInfo.physicalMemory,
                                  os: ProcessInfo.processInfo.operatingSystemVersion, pressure: stats.memory.pressure,
                                  thermal: stats.thermalState, battery: stats.battery, appsTitle: title, apps: apps, hideNames: hideNames)
    }
}

/// The small standalone window behind the ⌘K command "Share Vibe Card".
@MainActor
enum VibeCardWindow {
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    static func show(stats: SystemStats?) {
        guard let stats else { return }
        if let window {   // already open: bring it forward (its Refresh button updates the data)
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = VibeCardWindowView(stats: stats, initial: VibeCardRenderer.snapshot(stats: stats, hideNames: false))
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = String(localized: "Share Vibe Card")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false   // ARC owns it (our strong reference); AppKit must not also release it
        window.center()
        self.window = window
        // Closing frees the window, its stats reference and the icons; the next open builds a fresh one.
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
                closeObserver = nil
                VibeCardWindow.window?.contentViewController = nil
                VibeCardWindow.window = nil
            }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

private struct VibeCardWindowView: View {
    let stats: SystemStats
    @State var raw: VibeCardData
    @AppStorage("vibeCard.style") private var styleRaw = VibeCardStyle.dark.rawValue
    @AppStorage("vibeCard.redact") private var redact = false
    @State private var status: String?

    init(stats: SystemStats, initial: VibeCardData) {
        self.stats = stats
        _raw = State(initialValue: initial)
    }

    private var style: VibeCardStyle { VibeCardStyle(rawValue: styleRaw) ?? .dark }
    /// The snapshot with the redaction applied (the snapshot itself keeps real names).
    private var shown: VibeCardData {
        var d = raw
        if redact { d.apps = VibeCardData.redacted(d.apps); d.hideIcons = true }
        return d
    }

    var body: some View {
        VStack(spacing: 14) {
            VibeCardView(data: shown, style: style)
                .scaleEffect(0.5, anchor: .topLeading)
                .frame(width: 600, height: 315, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.quaternary))
                .accessibilityLabel(Text("Vibe Card preview"))
            HStack {
                Picker("Style", selection: $styleRaw) {
                    ForEach(VibeCardStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                Toggle("Hide app names", isOn: $redact)
                Spacer()
                Button("Refresh") { raw = VibeCardRenderer.snapshot(stats: stats, hideNames: false) }
                    .controlSize(.small)
            }
            HStack {
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Copy Image") { copy() }
                Button("Save PNG…") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640)
    }

    private func copy() {
        guard let png = VibeCardRenderer.png(shown, style: style) else { status = String(localized: "Couldn't make the image."); return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        status = String(localized: "Copied.")
    }

    private func save() {
        guard let png = VibeCardRenderer.png(shown, style: style) else { status = String(localized: "Couldn't make the image."); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = VibeCardRenderer.defaultFileName()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url, options: .atomic)
            status = String(localized: "Saved.")
        } catch {
            status = String(localized: "Couldn't save: \(error.localizedDescription)")
        }
    }
}
