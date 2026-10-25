// swift-tools-version: 6.1
// Minimal reproduction: views from a Skip Lite module that a consumer reaches through a
// non-Skip umbrella target (`@_exported import Inner`) are silently dropped inside @ViewBuilder.
import PackageDescription

let skipProducts: [Target.Dependency] = [
    .product(name: "SkipFoundation", package: "skip-foundation"),
    .product(name: "SkipUI", package: "skip-ui"),
]

let package = Package(
    name: "skip-umbrella-viewbuilder-repro",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "InnerUmbrella", targets: ["InnerUmbrella"]),
        .library(name: "UsesUmbrella", targets: ["UsesUmbrella"]),
        .library(name: "UsesDirect", targets: ["UsesDirect"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", exact: "1.9.19"),
        .package(url: "https://github.com/skiptools/skip-foundation.git", exact: "1.4.8"),
        .package(url: "https://github.com/skiptools/skip-ui.git", exact: "1.64.0"),
    ],
    targets: [
        // Skip Lite module (has Skip/skip.yml) that defines the views.
        .target(name: "Inner", dependencies: skipProducts,
                plugins: [.plugin(name: "skipstone", package: "skip")]),

        // Plain SwiftPM target, NO Skip/skip.yml: its only file is `@_exported import Inner`,
        // so Swift consumers can `import InnerUmbrella`.
        .target(name: "InnerUmbrella", dependencies: ["Inner"]),

        // Skip Lite module that reaches Inner through the umbrella -> views are dropped.
        .target(name: "UsesUmbrella", dependencies: ["InnerUmbrella"] + skipProducts,
                plugins: [.plugin(name: "skipstone", package: "skip")]),

        // Control: identical code, but `import Inner` directly -> views are composed.
        .target(name: "UsesDirect", dependencies: ["Inner"] + skipProducts,
                plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
