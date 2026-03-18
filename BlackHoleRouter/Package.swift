// swift-tools-version:5.9
// BlackHoleRouter - macOS audio routing GUI (qpwgraph equivalent for macOS + BlackHole)

import PackageDescription

let package = Package(
    name: "BlackHoleRouter",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "BlackHoleRouter",
            path: "Sources/BlackHoleRouter",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation")
            ]
        )
    ]
)
