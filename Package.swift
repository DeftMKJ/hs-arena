// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HearthStoneDraftAssistant",
    platforms: [
        .macOS(.v14),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "HearthDraftData",
            targets: ["HearthDraftData"]
        )
    ],
    targets: [
        .target(
            name: "HearthDraftData"
        ),
        .testTarget(
            name: "HearthDraftDataTests",
            dependencies: ["HearthDraftData"]
        )
    ]
)
