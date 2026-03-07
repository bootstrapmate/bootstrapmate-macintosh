// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BootstrapMate",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "bootstrapmate", targets: ["BootstrapMateCLI"]),
        .executable(name: "BootstrapMateApp", targets: ["BootstrapMateApp"]),
        .executable(name: "BootstrapMateHelper", targets: ["BootstrapMateHelper"]),
        .library(name: "BootstrapMateCore", targets: ["BootstrapMateCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "BootstrapMateCore"
        ),
        .executableTarget(
            name: "BootstrapMateCLI",
            dependencies: [
                "BootstrapMateCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .executableTarget(
            name: "BootstrapMateApp",
            dependencies: [
                "BootstrapMateCore"
            ]
        ),
        .executableTarget(
            name: "BootstrapMateHelper",
            dependencies: [
                "BootstrapMateCore"
            ]
        ),
        .testTarget(
            name: "BootstrapMateCoreTests",
            dependencies: ["BootstrapMateCore"]
        )
    ]
)
