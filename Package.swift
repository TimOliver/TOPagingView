// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TOPagingView",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(
            name: "TOPagingView",
            targets: ["TOPagingView"]
        )
    ],
    targets: [
        .target(
            name: "TOPagingView",
            path: "TOPagingView",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("Internal")
            ]
        )
    ]
)
