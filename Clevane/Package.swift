// swift-tools-version: 6.0
import PackageDescription

// Clevane app. ClevaneUI holds the SwiftUI screens and the system glue (pasteboard, sleep and lock events);
// the executable only starts it. All vault logic and cryptography live in VaultCore.
// Built as a Swift package because only the Command Line Tools are installed (no Xcode); see README.
let package = Package(
    name: "Clevane",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Clevane", targets: ["Clevane"]),
    ],
    dependencies: [.package(path: "../VaultCore")],
    targets: [
        .target(
            name: "ClevaneUI",
            dependencies: [.product(name: "VaultCore", package: "VaultCore")],
            swiftSettings: [.define("CLEVANE_SNAPSHOTS", .when(configuration: .debug))]
        ),
        .executableTarget(name: "Clevane", dependencies: ["ClevaneUI"]),
        .testTarget(name: "ClevaneUITests", dependencies: ["ClevaneUI"]),
    ]
)
