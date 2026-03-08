import PackageDescription

let package = Package(
    name: "Geolocate3D",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Geolocate3D",
            targets: ["Geolocate3D"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/facebook/meta-wearables-dat-ios", exact: "0.4.0"),
    ],
    targets: [
        .target(
            name: "Geolocate3D",
            dependencies: [
                .product(name: "MWDATCore", package: "meta-wearables-dat-ios"),
                .product(name: "MWDATCamera", package: "meta-wearables-dat-ios"),
            ],
            swiftSettings: [
            ]
        ),
    ]
)
