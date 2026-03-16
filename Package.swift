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
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "BootstrapMateCore",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/core"
        ),
        .executableTarget(
            name: "BootstrapMateCLI",
            dependencies: [
                "BootstrapMateCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/cli"
        ),
        .executableTarget(
            name: "BootstrapMateApp",
            dependencies: [
                "BootstrapMateCore"
            ],
            path: "Sources/app"
        ),
        .executableTarget(
            name: "BootstrapMateHelper",
            dependencies: [
                "BootstrapMateCore"
            ],
            path: "Sources/helper"
        ),
        .testTarget(
            name: "BootstrapMateCoreTests",
            dependencies: ["BootstrapMateCore"]
        )
    ]
)
