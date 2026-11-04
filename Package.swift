// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Notch", targets: ["Notch"]),
        // Loaded by /usr/bin/perl to read system Now Playing; copied into the app.
        .library(name: "NotchMediaBridge", type: .dynamic, targets: ["NotchMediaBridge"])
    ],
    targets: [
        .target(name: "NotchCore"),
        .executableTarget(name: "Notch", dependencies: ["NotchCore"]),
        // Hook bridge for coding assistants; copied next to the app binary.
        .executableTarget(name: "notch-hook", path: "Sources/NotchHook"),
        .target(name: "NotchMediaBridge", linkerSettings: [.linkedFramework("Foundation")]),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"])
    ],
    swiftLanguageModes: [.v5]
)
