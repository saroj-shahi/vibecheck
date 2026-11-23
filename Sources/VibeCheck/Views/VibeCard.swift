import AppKit
import SwiftUI

enum VibeCardStyle: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var title: String { self == .light ? String(localized: "Light") : String(localized: "Dark") }
}

/// Everything the Vibe Card shows, as plain values: built from a snapshot of the stats, rendered without the deck.
struct VibeCardData {
    struct App: Identifiable {
        let id: Int
        let name: String
        let value: String
        let icon: NSImage?
    }

    var vibe: Vibe
    var verdict: String
    var chip: String
    var ram: String
    var macOS: String
    var pressure: String
    var thermal: String
    /// nil on desktops.
    var power: String?
    var appsTitle: String
    var apps: [App]
    var date: Date
    /// "Hide app names": no icon slot at all.
    var hideIcons = false

    var vibeTitle: String { vibe.title }
    /// "Apple M5 · 32 GB · macOS 26.1"
    var macLine: String { [chip, ram, macOS].filter { !$0.isEmpty }.joined(separator: " · ") }

    // MARK: Pure helpers

    nonisolated static func thermalWords(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: String(localized: "Cool")
        case .fair: String(localized: "Warm")
        case .serious, .critical: String(localized: "Throttling")
        @unknown default: String(localized: "Warm")
        }
    }

    nonisolated static func powerText(_ battery: BatterySample) -> String? {
        guard battery.present else { return nil }
        if battery.onAC {
            if let watts = battery.chargerWatts { return String(localized: "Plugged in, \(watts) W charger") }
            return String(localized: "Plugged in")
        }
        return String(localized: "On battery, \(Int(battery.percent.rounded()))%")
    }

    nonisolated static func ramText(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return "\(Int(gb.rounded())) GB"
    }

    nonisolated static func macOSText(_ v: OperatingSystemVersion) -> String {
        v.patchVersion == 0 ? "macOS \(v.majorVersion).\(v.minorVersion)" : "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// "App 1", "App 2", … and no icons.
    nonisolated static func redacted(_ apps: [App]) -> [App] {
        apps.enumerated().map { App(id: $0.offset, name: String(localized: "App \($0.offset + 1)"), value: $0.element.value, icon: nil) }
    }

    nonisolated static func build(vibe: Vibe, verdict: String, chip: String, memoryBytes: UInt64, os: OperatingSystemVersion,
                                  pressure: MemoryPressure, thermal: ProcessInfo.ThermalState, battery: BatterySample,
                                  appsTitle: String, apps: [App], hideNames: Bool, date: Date = Date()) -> VibeCardData {
        let shown = Array(apps.prefix(3))
        return VibeCardData(vibe: vibe, verdict: verdict, chip: chip, ram: ramText(memoryBytes), macOS: macOSText(os),
                            pressure: pressure.label, thermal: thermalWords(thermal), power: powerText(battery),
                            appsTitle: appsTitle, apps: hideNames ? redacted(shown) : shown, date: date, hideIcons: hideNames)
    }
}

/// The shareable card: fixed 1200 × 630 points, explicit colors so it looks the same wherever it's rendered.
struct VibeCardView: View {
    static let size = CGSize(width: 1200, height: 630)
    let data: VibeCardData
    let style: VibeCardStyle

    private var dark: Bool { style == .dark }
    private var ink: Color { dark ? Color(hex: 0xF5F7FF) : Color(hex: 0x141833) }
    private var secondary: Color { dark ? Color(hex: 0xAEB4D6) : Color(hex: 0x141833).opacity(0.62) }
    private var panel: Color { dark ? Color.white.opacity(0.07) : Color.white.opacity(0.75) }
    private var stateColor: Color {
        switch data.vibe {
        case .vibing: Color(hex: 0x3DE0B5)
        case .mid: Color(hex: 0xFFC542)
        case .cooked: Color(hex: 0xFF5A5F)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 48) {
                hero.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                details.frame(width: 500)
            }
            footer.padding(.top, 20)
        }
        .padding(56)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(background)
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private var background: some View {
        LinearGradient(colors: dark ? [Color(hex: 0x252A52), Color(hex: 0x0B0E22)] : [Color(hex: 0xF5F7FF), Color(hex: 0xDDE3FA)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 32) {
                CardRing(vibe: data.vibe, color: stateColor, track: ink.opacity(0.14))
                    .frame(width: 170, height: 170)
                Text(data.vibeTitle)
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .tracking(-1.5)
                    .foregroundStyle(stateColor)
                    .lineLimit(1).minimumScaleFactor(0.4)
            }
            Text(data.verdict)
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(5).minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            row(String(localized: "Mac"), data.macLine)
            row(String(localized: "Memory pressure"), data.pressure)
            row(String(localized: "Thermals"), data.thermal)
            if let power = data.power { row(String(localized: "Power"), power) }
            Divider().overlay(ink.opacity(0.15)).padding(.vertical, 4)
            Text(data.appsTitle)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(secondary)
                .lineLimit(1).minimumScaleFactor(0.5)
            // One name size for all rows: the largest at which every name fits.
            ViewThatFits(in: .horizontal) {
                ForEach([26.0, 24, 22, 20, 18, 16, 14], id: \.self) { size in appRows(size: size, scale: 1) }
                appRows(size: 14, scale: 0.5)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(panel))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(ink.opacity(0.10), lineWidth: 1))
    }

    private func appRows(size: CGFloat, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(data.apps) { app in
                HStack(spacing: 14) {
                    if !data.hideIcons {
                        Group {
                            if let icon = app.icon {
                                Image(nsImage: icon).resizable()
                            } else {
                                Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(secondary)
                            }
                        }
                        .frame(width: 36, height: 36)
                    }
                    Text(app.name)
                        .font(.system(size: size, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink)
                        .lineLimit(1).minimumScaleFactor(scale)
                    Spacer(minLength: 8)
                    Text(app.value)
                        .font(.system(size: 26, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(secondary)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .layoutPriority(1)
                }
                .frame(height: 38)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(secondary)
                .lineLimit(1).minimumScaleFactor(0.5)
                .fixedSize()
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.4)
        }
    }

    private var footer: some View {
        HStack {
            (Text("Vibe").foregroundStyle(ink)
                + Text("Check").foregroundStyle(LinearGradient(colors: [Color(hex: 0x3DE0B5), Color(hex: 0x36B6F2), Color(hex: 0x8B6CFF)],
                                                              startPoint: .leading, endPoint: .trailing)))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .tracking(-0.64)
            Spacer()
            Text(data.date.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(secondary)
        }
    }
}

/// The vibe ring drawn with shapes (same fill levels and colors as `VibeRing`). `VibeRing` itself can't be
/// used here: its wobble is an AppKit view and its symbol / animation don't render through `ImageRenderer`.
private struct CardRing: View {
    let vibe: Vibe
    let color: Color
    let track: Color

    var body: some View {
        GeometryReader { geo in
            let line = geo.size.width * 0.12
            ZStack {
                Circle().stroke(track, lineWidth: line)
                Circle().trim(from: 0, to: vibe.ringFill)
                    .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(line / 2)
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
