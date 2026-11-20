// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LeonApp",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LeonApp", targets: ["LeonApp"])],
    dependencies: [
        .package(path: "Vendor/SwiftMath")
    ],
    targets: [
        .executableTarget(name: "LeonApp", dependencies: ["SwiftMath"])
    ]
)
