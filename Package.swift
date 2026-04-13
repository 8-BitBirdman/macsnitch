// swift-tools-version: 5.9
// Package.swift — used ONLY for running `swift test` from the command line.
// The actual app and extension are built via MacSnitch.xcodeproj.
// GRDB is managed by Xcode's SPM integration (not declared here to avoid conflicts).

import PackageDescription

let package = Package(
    name: "MacSnitchTests",
    platforms: [.macOS(.v13)],
    products: [],
    dependencies: [],
    targets: [
        // Shared types compiled as a library so the test target can import them.
        .target(
            name: "MacSnitchShared",
            path: "Shared"
        ),

        // Unit tests — run with: swift test
        // Note: Tests that require GRDB (RuleStore) are exercised via Xcode only.
        .testTarget(
            name: "MacSnitchTests",
            dependencies: ["MacSnitchShared"],
            path: "Tests"
        ),
    ]
)
