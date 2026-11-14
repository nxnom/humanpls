// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "humanpls",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "humanpls", targets: ["humanpls"])],
    targets: [
        // Everything that has no UI: job format, answer text, history, socket protocol. Unit tested.
        .target(name: "HumanplsCore"),
        // The app and the CLI are one binary: no args = menu bar app, args = CLI client.
        .executableTarget(name: "humanpls", dependencies: ["HumanplsCore"]),
        .testTarget(name: "HumanplsCoreTests", dependencies: ["HumanplsCore"]),
    ],
    swiftLanguageModes: [.v5]
)
