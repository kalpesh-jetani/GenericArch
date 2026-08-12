// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.iOS(.v17), .macOS("26.6")],
    products: [.library(name: "Core", targets: ["Core"])],
    targets: [
        .target(name: "Core", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "CoreTests", dependencies: ["Core"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
