// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Geolocate3D",
    platforms: [
        .iOS(.v17),
    ],
    targets: [
        .executableTarget(
            name: "Geolocate3D"
        ),
    ]
)
