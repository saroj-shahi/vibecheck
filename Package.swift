// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VibeCheck",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        // Shared with the widget extension: the snapshot the app writes into the app group.
        .target(name: "VibeCheckShared", path: "Sources/VibeCheckShared"),
        .executableTarget(
            name: "VibeCheck",
            dependencies: ["VibeCheckShared"],
            path: "Sources/VibeCheck",
            exclude: ["Resources/AppShortcuts.xcstrings"], // compiled by build.sh straight into the app
            resources: [.process("Resources/Localizable.xcstrings")],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("AppIntents"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("CoreWLAN"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        // WidgetKit extension. SwiftPM builds the executable; build.sh wraps it into VibeCheckWidget.appex.
        .executableTarget(
            name: "VibeCheckWidget",
            dependencies: ["VibeCheckShared"],
            path: "Sources/VibeCheckWidget",
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                .linkedFramework("WidgetKit"),
                .linkedFramework("AppIntents"), // the Control Center toggle's intent
                // Extensions start in Foundation's NSExtensionMain (as Xcode links them), not Swift's main:
                // without it the widget traps while bootstrapping.
                .unsafeFlags(["-Xlinker", "-application_extension", "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
            ]
        ),
        .testTarget(name: "VibeCheckTests", dependencies: ["VibeCheck", "VibeCheckShared"], path: "Tests/VibeCheckTests"),
    ]
)
