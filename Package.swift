// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hush",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        // Models, persistence, undo, summaries. No AppKit/SwiftUI imports.
        .target(name: "HushCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        // The menu bar app: SwiftUI + AppKit.
        .executableTarget(name: "Hush", dependencies: ["HushCore"]),
        .testTarget(name: "HushCoreTests", dependencies: ["HushCore"]),
    ]
)
