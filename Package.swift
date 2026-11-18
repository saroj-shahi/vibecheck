// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VibeCheck",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VibeCheck",
            path: "Sources/VibeCheck",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("AppIntents"),
            ]
        ),
        .testTarget(name: "VibeCheckTests", dependencies: ["VibeCheck"], path: "Tests/VibeCheckTests"),
    ]
)
