// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TarabBannerHider",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "TarabBannerHider",
            type: .dynamic,
            targets: ["TarabBannerHider"]
        )
    ],
    targets: [
        .target(
            name: "TarabBannerHider",
            path: "Sources/TarabBannerHider",
            publicHeadersPath: "include",
            resources: [
                .process("Resources")
            ],
            cSettings: [
                .unsafeFlags(["-fobjc-arc"])
            ]
        )
    ]
)
