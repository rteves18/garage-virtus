// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GarageVirtusKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GarageVirtusKit", targets: ["GarageVirtusKit"]),
        .executable(name: "garage-virtus-mcp", targets: ["GarageVirtusMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
    ],
    targets: [
        .target(name: "GarageVirtusKit"),
        .executableTarget(
            name: "GarageVirtusMCP",
            dependencies: ["GarageVirtusKit", .product(name: "MCP", package: "swift-sdk")]
        ),
        .testTarget(
            name: "GarageVirtusKitTests",
            dependencies: ["GarageVirtusKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
