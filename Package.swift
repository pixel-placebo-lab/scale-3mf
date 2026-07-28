// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Scale3MF",
    platforms: [.macOS(.v14)],
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
            resources: [
                .copy("fastener-dimensions.json"),
                .copy("fastener-heights.json"),
                .copy("extrusion-profiles.json"),
                .copy("app_icon.icns"),
                .copy("app_icon.png")
            ],
            swiftSettings: [
                .define("SWIFT_PACKAGE")
            ]
        )
    ]
)