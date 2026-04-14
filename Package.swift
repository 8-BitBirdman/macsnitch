// swift-tools-version: 5.9
// Package.swift — used ONLY for running `swift test` from the command line.
// The actual app and extension are built via MacSnitch.xcodeproj.
// GRDB is managed by Xcode's SPM integration and is NOT declared here to avoid conflicts.

import PackageDescription

let package = Package(
    name: "MacSnitchTests",
    platforms: [.macOS(.v13)],
    products: [],
    dependencies: [],
    targets: [
        // Shared types (ConnectionInfo, Rule, VerdictReply, etc.)
        .target(
            name: "MacSnitchShared",
            path: "Shared"
        ),

        // Extension logic needed by unit tests (RuleCache, DNSResolver).
        // These have no framework dependencies so they compile cleanly under SPM.
        .target(
            name: "MacSnitchExtensionCore",
            dependencies: ["MacSnitchShared"],
            path: "NetworkExtension",
            exclude: [
                "main.swift",               // calls NEProvider.startSystemExtensionMode()
                "FilterProvider.swift",     // imports NetworkExtension framework
                "FilterControlProvider.swift", // imports NetworkExtension framework
            ]
        ),

        // Unit tests — run with: swift test
        .testTarget(
            name: "MacSnitchTests",
            dependencies: ["MacSnitchShared", "MacSnitchExtensionCore"],
            path: "Tests"
        ),
    ]
)
