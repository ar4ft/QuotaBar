// swift-tools-version: 6.0
import PackageDescription

var appDependencies: [Target.Dependency] = ["QuotaCore"]
var binaryTargets: [Target] = []
var appLinkerSettings: [LinkerSetting] = []
#if os(macOS)
// Sparkle is used only by the macOS application; core tests remain portable.
appDependencies.append("Sparkle")
binaryTargets.append(.binaryTarget(name: "Sparkle",
    url: "https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-for-Swift-Package-Manager.zip",
    checksum: "8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606"))
appLinkerSettings.append(.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]))
#endif

let package = Package(
    name: "QuotaBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "QuotaBar", targets: ["QuotaBar"])],
    targets: [
        .target(name: "QuotaCore"),
        .executableTarget(name: "QuotaBar", dependencies: appDependencies, linkerSettings: appLinkerSettings),
        .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"])
    ] + binaryTargets,
    swiftLanguageModes: [.v5]
)
