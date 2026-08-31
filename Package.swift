// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FLEXDInject",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "FLEXDInject",
            type: .dynamic,
            targets: ["FLEXDInject"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/TimOliver/fleXD.git",
            branch: "main"
        )
    ],
    targets: [
        .target(
            name: "FLEXDInject",
            dependencies: [
                .product(name: "FLEX", package: "fleXD")
            ],
            path: "Sources/FLEXDInject",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("Foundation")
            ]
        )
    ]
)
