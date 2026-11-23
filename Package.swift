// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TreeYard",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TreeYard", path: "Sources/TreeYard")
    ]
)
