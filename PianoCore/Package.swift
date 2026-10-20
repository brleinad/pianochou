// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PianoCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PianoCore", targets: ["PianoCore"]),
    ],
    targets: [
        .target(
            name: "PianoCore",
            // Audio analysis runs in real time; keep it optimized even in Debug app builds.
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        .executableTarget(name: "score-dump", dependencies: ["PianoCore"]),
        .testTarget(
            name: "PianoCoreTests",
            dependencies: ["PianoCore"],
            resources: [.copy("../Fixtures")]
        ),
    ]
)
