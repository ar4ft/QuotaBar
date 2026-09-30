// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "QuotaBar", targets: ["QuotaBar"])],
    targets: [
        .target(name: "QuotaCore"),
        .executableTarget(name: "QuotaBar", dependencies: ["QuotaCore"]),
        .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"])
    ],
    swiftLanguageModes: [.v5]
)
