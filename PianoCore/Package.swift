// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PianoCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PianoCore", targets: ["PianoCore"]),
    ],
    targets: [
        .target(name: "PianoCore"),
        .testTarget(
            name: "PianoCoreTests",
            dependencies: ["PianoCore"],
            resources: [.copy("../Fixtures")]
        ),
    ]
)
