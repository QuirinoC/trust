// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Trust",
    platforms: [
        .iOS(.v18),
        .macOS(.v13)
    ],
    products: [
        .library(name: "TrustCore", targets: ["TrustCore"])
    ],
    targets: [
        .target(
            name: "TrustCore",
            path: "Sources/TrustCore"
        ),
        .testTarget(
            name: "TrustCoreTests",
            dependencies: ["TrustCore"],
            path: "Tests/TrustCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
