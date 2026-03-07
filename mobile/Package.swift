import PackageDescription

let package = Package(
    name: "Geolocate3D",
    platforms: [
        .iOS(.v17),
    ],
    dependencies: [
        .package(url: "https://github.com/facebook/meta-wearables-dat-ios/", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "Geolocate3D",
            dependencies: [
                .product(name: "MWDATCore", package: "meta-wearables-dat-ios"),
                .product(name: "MWDATCamera", package: "meta-wearables-dat-ios"),
            ]
        ),
    ]
)
