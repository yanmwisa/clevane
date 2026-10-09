// swift-tools-version: 6.0
import PackageDescription

// VaultCore: vault file, keys, session and model. It imports neither SwiftUI nor AppKit.
let package = Package(
    name: "VaultCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VaultCore", targets: ["VaultCore"]),
    ],
    dependencies: [
        // Argon2id only: CryptoKit offers no password key derivation. Inspected before adoption:
        // tag 0.11.0 signed by Frank Denis, commit cfd195c76882aa9b997560ca7cb95d72fbf5db00, ISC license,
        // bundles static libsodium 1.0.22. Change this version only after a new inspection.
        .package(url: "https://github.com/jedisct1/swift-sodium.git", exact: "0.11.0"),
    ],
    targets: [
        .target(name: "VaultCore", dependencies: [.product(name: "Sodium", package: "swift-sodium")]),
        .testTarget(name: "VaultCoreTests", dependencies: ["VaultCore"]),
    ]
)
