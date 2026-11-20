// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "LeonNativeIOS", platforms: [.macOS(.v13), .iOS(.v16)], products: [
    .library(name: "LeonCore", targets: ["LeonCore"])
], targets: [
    .target(name: "LeonCore", linkerSettings: [.linkedLibrary("z")])
])
