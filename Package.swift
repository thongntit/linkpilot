// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LinkPilot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "LinkPilot"),
        .testTarget(name: "LinkPilotTests", dependencies: ["LinkPilot"])
    ],
    swiftLanguageModes: [.v5]
)
