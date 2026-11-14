// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PofudukCore",
    defaultLocalization: "tr",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PofudukCore", targets: ["PofudukCore"])
    ],
    targets: [
        .target(name: "PofudukCore"),
        .testTarget(name: "PofudukCoreTests", dependencies: ["PofudukCore"])
    ]
)
