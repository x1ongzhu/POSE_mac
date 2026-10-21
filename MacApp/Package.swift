// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CloudpilotMac",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CloudpilotMac", targets: ["CloudpilotMac"])],
    targets: [.executableTarget(name: "CloudpilotMac")]
)
