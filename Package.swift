// swift-tools-version: 6.2
import PackageDescription

/// Treat all warnings as errors. Applies to this package's targets only.
let strictSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "KirbyiOS",
    platforms: [
        .iOS("18.4"),
    ],
    products: [
        .library(name: "KirbyiOS", targets: ["KirbyiOS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/WildFunction/WildFunctionKit.git", from: "0.2.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.12.2"),
    ],
    targets: [
        .target(
            name: "KirbyiOS",
            dependencies: [
                .product(name: "WildFunctionKit", package: "WildFunctionKit"),
                .product(name: "Alamofire", package: "Alamofire"),
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(name: "KirbyiOSTests", dependencies: ["KirbyiOS"], swiftSettings: strictSettings),
    ],
    swiftLanguageModes: [.v6]
)
