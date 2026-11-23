// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hush",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        // Backend-owned: models, persistence, services. No AppKit/SwiftUI imports.
        .target(name: "HushCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        // Frontend-owned: SwiftUI/AppKit app.
        .executableTarget(name: "Hush", dependencies: ["HushCore"]),
        .testTarget(name: "HushCoreTests", dependencies: ["HushCore"]),
    ]
)
