// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VibeCheck",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VibeCheck",
            path: "Sources/VibeCheck",
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
        .testTarget(name: "VibeCheckTests", dependencies: ["VibeCheck"], path: "Tests/VibeCheckTests"),
    ]
)
