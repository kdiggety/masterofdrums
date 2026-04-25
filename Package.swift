// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MasterOfDrums",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MasterOfDrums", targets: ["MasterOfDrums"])
    ],
    targets: [
        .executableTarget(
            name: "MasterOfDrums",
            path: "Sources",
            resources: [
                .copy("Audio/Samples")
            ]
        ),
        .testTarget(
            name: "MasterOfDrumsTests",
            dependencies: ["MasterOfDrums"],
            path: "Tests/MasterOfDrumsTests"
        )
    ]
)
