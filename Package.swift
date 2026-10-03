// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OnTimelyCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "OnTimelyCore", targets: ["OnTimelyCore"])],
    targets: [
        .target(name: "OnTimelyCore", path: "OnTimely/Core"),
        .testTarget(name: "OnTimelyCoreTests", dependencies: ["OnTimelyCore"], path: "Tests/OnTimelyCoreTests")
    ]
)
