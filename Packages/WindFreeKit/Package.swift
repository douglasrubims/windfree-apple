// swift-tools-version: 6.0
import PackageDescription

// Núcleo compartilhado entre as plataformas. Não depende de SwiftUI nem de AppKit/UIKit:
// apenas Foundation, Observation, Security (Keychain) e os.
let package = Package(
    name: "WindFreeKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "WindFreeKit", targets: ["WindFreeKit"]),
    ],
    targets: [
        .target(name: "WindFreeKit"),
        .testTarget(name: "WindFreeKitTests", dependencies: ["WindFreeKit"]),
    ]
)
