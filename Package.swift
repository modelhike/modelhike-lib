// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ModelHike",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(name: "ModelHike", targets: ["ModelHike"]),
        .executable(name: "DevTester", targets: ["DevTester"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.96.0"),
    ],
    targets: [
        .target(
            name: "ModelHikeDSL",
            path: "DSL",
            resources: [
                .copy("modelHike.dsl.md"),
                .copy("codelogic.dsl.md"),
                .copy("templatesoup.dsl.md"),
            ]
        ),
        .target(
            name: "ModelHike",
            dependencies: ["ModelHikeDSL"],
            path: "Sources",
            exclude: [
                "_Common_/ThirdParty/Codextended/LICENSE",
                "_Common_/ThirdParty/Codextended/README.md"
            ],
            swiftSettings: [
                //.unsafeFlags([
                //    //"-Xfrontend", "-strict-concurrency=complete",
                //    "-Xfrontend", "-warn-long-function-bodies=200",
                //    "-Xfrontend", "-warn-long-expression-type-checking=200"]
                //)
            ]
        ),
        .executableTarget(
            name: "DevTester",
            dependencies: [
                "ModelHike",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
            ],
            path: "DevTester",
            resources: [.process("Assets")]
        ),
        .testTarget(
            name: "ModelHikeTests",
            dependencies: ["ModelHike"],
            path: "Tests"
        ),
    ]
)
