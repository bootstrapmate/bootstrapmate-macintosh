// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BootstrapMate",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "bootstrapmate", targets: ["BootstrapMateCLI"]),
        .library(name: "BootstrapMateCore", targets: ["BootstrapMateCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "BootstrapMateCore",
            path: ".",
            exclude: [
                "cli",
                "Resources",
                "scripts",
                "examples",
                "LICENSE",
                "README.md"
            ],
            sources: [
                "Managers",
                "Utilities"
            ]
        ),
        .executableTarget(
            name: "BootstrapMateCLI",
            dependencies: [
                "BootstrapMateCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "cli",
            sources: ["."]
        )
    ]
)
