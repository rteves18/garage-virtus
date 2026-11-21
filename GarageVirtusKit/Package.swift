// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GarageVirtusKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GarageVirtusKit", targets: ["GarageVirtusKit"]),
    ],
    targets: [
        .target(name: "GarageVirtusKit"),
        .testTarget(
            name: "GarageVirtusKitTests",
            dependencies: ["GarageVirtusKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
