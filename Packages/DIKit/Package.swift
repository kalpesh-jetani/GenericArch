// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DIKit",
    platforms: [.iOS(.v17), .macOS("26.6")],
    products: [.library(name: "DIKit", targets: ["DIKit"])],
    dependencies: [.package(path: "../Core")],
    targets: [
        .target(name: "DIKit", dependencies: ["Core"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "DIKitTests", dependencies: ["DIKit", "Core"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
