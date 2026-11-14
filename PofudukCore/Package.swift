// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PofudukCore",
    defaultLocalization: "tr",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PofudukCore", targets: ["PofudukCore"]),
        // Console demo of Pofuduk's brain with live data (Windows/macOS): `scripts\pofuduk.cmd Ankara`
        .executable(name: "PofudukDemo", targets: ["PofudukDemo"])
    ],
    targets: [
        .target(name: "PofudukCore"),
        .executableTarget(name: "PofudukDemo", dependencies: ["PofudukCore"]),
        .testTarget(name: "PofudukCoreTests", dependencies: ["PofudukCore"])
    ]
)
