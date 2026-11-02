// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Capri",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Capri", path: "Sources/Capri")
    ]
)
