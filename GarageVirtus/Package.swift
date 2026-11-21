// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "GarageVirtus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GarageVirtus",
            path: "Sources/GarageVirtus"
        )
    ]
)
