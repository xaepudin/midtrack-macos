// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SongSeeker",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SongSeekerKit", targets: ["SongSeekerKit"]),
        .executable(name: "SongSeeker", targets: ["SongSeeker"]),
    ],
    targets: [
        .target(name: "SongSeekerKit"),
        .executableTarget(name: "SongSeeker", dependencies: ["SongSeekerKit"]),
        .testTarget(name: "SongSeekerKitTests", dependencies: ["SongSeekerKit"]),
    ],
    // The reader watches a child process and hands snapshots to the main thread by
    // hand; Swift 5 language mode keeps the concurrency checker out of the way
    // without giving up Swift 6 tooling.
    swiftLanguageModes: [.v5]
)
