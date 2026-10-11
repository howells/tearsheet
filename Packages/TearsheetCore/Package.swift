// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TearsheetCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TearsheetCore", targets: ["TearsheetCore"]),
    ],
    targets: [
        .target(name: "TearsheetCore"),
        .testTarget(name: "TearsheetCoreTests", dependencies: ["TearsheetCore"]),
    ]
)
