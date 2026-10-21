// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CliProxyQuota",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CliProxyQuota", targets: ["CliProxyQuota"])],
    targets: [
        .target(name: "QuotaCore"),
        .executableTarget(name: "CliProxyQuota", dependencies: ["QuotaCore"]),
        .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"])
    ],
    swiftLanguageModes: [.v5]
)
