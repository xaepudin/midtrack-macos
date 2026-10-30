// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Midtrack",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MidtrackKit", targets: ["MidtrackKit"]),
        .executable(name: "Midtrack", targets: ["Midtrack"]),
    ],
    targets: [
        .target(name: "MidtrackKit"),
        .executableTarget(name: "Midtrack", dependencies: ["MidtrackKit"]),
        .testTarget(name: "MidtrackKitTests", dependencies: ["MidtrackKit"]),
    ],
    // The reader watches a child process and hands snapshots to the main thread by
    // hand; Swift 5 language mode keeps the concurrency checker out of the way
    // without giving up Swift 6 tooling.
    swiftLanguageModes: [.v5]
)
