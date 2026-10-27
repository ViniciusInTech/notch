// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notch",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Notch", targets: ["Notch"])],
    targets: [
        .target(name: "NotchCore"),
        .executableTarget(name: "Notch", dependencies: ["NotchCore"]),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"])
    ],
    swiftLanguageModes: [.v5]
)
