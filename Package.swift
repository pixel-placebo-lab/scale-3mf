// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Scale3MF",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "Scale3MF", targets: ["Scale3MF"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.16")
    ],
    targets: [
        .executableTarget(
            name: "Scale3MF",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            swiftSettings: [
                .define("SWIFT_PACKAGE")
            ]
        )
    ]
)
