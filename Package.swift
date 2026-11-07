// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ButtonS",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ButtonS", targets: ["ButtonSApp"]),
        .library(name: "ButtonSCore", targets: ["ButtonSCore"]),
        .library(name: "ButtonSMac", targets: ["ButtonSMac"]),
        .library(name: "ButtonSVoice", targets: ["ButtonSVoice"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "ButtonSCore",
            resources: [
                .copy("../../Resources/Data"),
                .copy("../../Resources/Icons"),
            ]
        ),
        .target(
            name: "ButtonSMac",
            dependencies: ["ButtonSCore"]
        ),
        .target(
            name: "ButtonSVoice",
            dependencies: [
                "ButtonSMac",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .executableTarget(
            name: "ButtonSApp",
            dependencies: [
                "ButtonSCore",
                "ButtonSMac",
                "ButtonSVoice",
            ]
        ),
        .testTarget(
            name: "ButtonSCoreTests",
            dependencies: ["ButtonSCore"]
        ),
    ]
)
