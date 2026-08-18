// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "FastScreenerMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FastScreenerMacSpike"
        ),
        .executableTarget(
            name: "FastScreenerMac"
        ),
    ]
)
