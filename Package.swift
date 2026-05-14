// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperDictate",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WhisperDictate",
            path: "Sources/WhisperDictate",
            // Carbon framework for global hotkeys (no Accessibility permission required)
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
            ]
        )
    ]
)
