// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TarabRemoteBanner",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "TarabRemoteBanner",
            type: .dynamic,
            targets: ["TarabRemoteBanner"]
        )
    ],
    targets: [
        .target(
            name: "TarabRemoteBanner",
            path: "Sources/TarabRemoteBanner",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("Foundation")
            ]
        )
    ]
)
