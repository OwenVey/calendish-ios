// swift-tools-version: 6.0
// Pins the repo's lint and format tools. Run them through ./scripts/format.sh and ./scripts/lint.sh,
// which build this package on first use. Bump versions here, then run `swift package update`.
import PackageDescription

let package = Package(
    name: "BuildTools",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/SwiftFormat", exact: "0.63.1"),
        .package(url: "https://github.com/realm/SwiftLint", exact: "0.65.1"),
    ],
    targets: [
        // SwiftPM needs a target to resolve dependencies; the tools are run as dependency products.
        .target(name: "BuildTools", path: "Sources"),
    ]
)
