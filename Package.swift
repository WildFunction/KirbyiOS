// swift-tools-version: 6.2
import PackageDescription

/// Warnings are errors only when KIRBYIOS_STRICT is set (CI and local development).
/// It must stay off for consumers: Xcode suppresses warnings in remote packages,
/// and combining that with warnings-as-errors fails the build.
let strictSettings: [SwiftSetting] = Context.environment["KIRBYIOS_STRICT"] == nil
    ? []
    : [.treatAllWarnings(as: .error)]

let package = Package(
    name: "KirbyiOS",
    platforms: [
        .iOS("18.4"),
    ],
    products: [
        .library(name: "KirbyiOS", targets: ["KirbyiOS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/WildFunction/WildFunctionKit.git", from: "0.2.1"),
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
