import AppKit
import Foundation
import SwiftUI
import Testing
@testable import VibeCheck

@MainActor
struct VibeCardTests {
    static let longName = "Google Chrome Helper (Renderer)"
    static let longVerdict = "Your Mac is cooked: memory pressure is critical and the fans are loud. Google Chrome Helper (Renderer) (14 processes) grew 6.4 GB in the last hour."

    static func apps() -> [VibeCardData.App] {
        [.init(id: 0, name: longName, value: "12.4 GB", icon: NSImage(named: NSImage.applicationIconName)),
         .init(id: 1, name: "Xcode", value: "4.1 GB", icon: nil),
         .init(id: 2, name: "Slack", value: "1.2 GB", icon: nil),
         .init(id: 3, name: "Extra", value: "1 GB", icon: nil)]
    }

    static func data(hide: Bool = false, battery: BatterySample = BatterySample()) -> VibeCardData {
        VibeCardData.build(vibe: .cooked, verdict: longVerdict, chip: "Apple M5 Max", memoryBytes: 34_359_738_368,
                           os: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0),
                           pressure: .critical, thermal: .serious, battery: battery, appsTitle: "Top apps by memory",
                           apps: apps(), hideNames: hide)
    }

    @Test func redactionHidesNamesAndIcons() {
        let d = Self.data(hide: true)
        #expect(d.apps.map(\.name) == ["App 1", "App 2", "App 3"])
        #expect(d.apps.allSatisfy { $0.icon == nil })
        #expect(d.apps.map(\.value) == ["12.4 GB", "4.1 GB", "1.2 GB"])
        let plain = Self.data()
        #expect(plain.apps.count == 3)
        #expect(plain.apps[0].name == Self.longName)
    }

    @Test func powerText() {
        var b = BatterySample()
        #expect(VibeCardData.powerText(b) == nil)               // desktop
        b.present = true; b.onAC = false; b.percent = 64
        #expect(VibeCardData.powerText(b) == "On battery, 64%")
        b.onAC = true; b.chargerWatts = 68
        #expect(VibeCardData.powerText(b) == "Plugged in, 68 W charger")
        b.chargerWatts = nil
        #expect(VibeCardData.powerText(b) == "Plugged in")
    }

    @Test func thermalAndMacWords() {
        #expect(VibeCardData.thermalWords(.nominal) == "Cool")
        #expect(VibeCardData.thermalWords(.fair) == "Warm")
        #expect(VibeCardData.thermalWords(.serious) == "Throttling")
        #expect(VibeCardData.thermalWords(.critical) == "Throttling")
        let d = Self.data()
        #expect(d.ram == "32 GB")
        #expect(d.macOS == "macOS 26.1")
        #expect(d.macLine == "Apple M5 Max · 32 GB · macOS 26.1")
        #expect(d.power == nil)
    }

    @Test func rendersBothStylesAt2x() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vibecard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var battery = BatterySample(); battery.present = true; battery.onAC = true; battery.chargerWatts = 68
        for style in VibeCardStyle.allCases {
            let image = try #require(VibeCardRenderer.cgImage(Self.data(battery: battery), style: style))
            #expect(image.width == 2400 && image.height == 1260)
            let png = try #require(VibeCardRenderer.png(Self.data(battery: battery), style: style))
            let url = folder.appendingPathComponent("vibecard-\(style.rawValue).png")
            try png.write(to: url)
            print("VIBECARD_PNG \(url.path)")
        }
    }

    @Test func fileName() {
        let name = VibeCardRenderer.defaultFileName(Date(timeIntervalSince1970: 0))
        #expect(name.hasPrefix("VibeCheck-") && name.hasSuffix(".png") && name.count == "VibeCheck-2026-01-01-0000.png".count)
    }
}
