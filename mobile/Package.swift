// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Geolocate3D",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "Geolocate3D",
            targets: ["Geolocate3D"]
        ),
    ],
    targets: [
        .target(
            name: "Geolocate3D"
        ),
    ]
)
