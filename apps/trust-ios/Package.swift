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
    dependencies: [
        .package(url: "https://github.com/PhoneNumberKit/PhoneNumberKit.git", exact: "5.0.13")
    ],
    targets: [
        .target(
            name: "TrustCore",
            dependencies: [.product(name: "PhoneNumberKit", package: "PhoneNumberKit")],
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
