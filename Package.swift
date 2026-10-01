// swift-tools-version:5.9

import PackageDescription
import Foundation

#if os(Linux) || os(Windows)
let platformExcludes = ["Apple", "Mac", "iOS"]
#else
let platformExcludes: [String] = []
#endif

// `getenv`, not `ProcessInfo`'s environment: swift.org Swift 6.3.1 crashes compiling
// any manifest that reads it (ActiveUI's CROSSPLATFORM_PLAN.md, fact 8).
let isGitHubActions = getenv("GITHUB_ACTIONS").map { String(cString: $0) } == "true"

// **The library alone**, for a cross-compile from the Mac (ActiveUI's
// ACTIVEUI_CROSS, or SWIFTTERM_LIBRARY_ONLY). The tools' dependencies
// (argument parser, DocC plugin) crash swift.org Swift 6.3.1's manifest loading
// with the Linux SDK, and the Metal shader is Apple's. Unset, nothing changes.
// (Local change.)
let libraryOnly = getenv("ACTIVEUI_CROSS") != nil || getenv("SWIFTTERM_LIBRARY_ONLY") != nil
let disableBenchmark = true
let benchmarkDependencies: [Package.Dependency] = (isGitHubActions || disableBenchmark) ? [] : [
    .package(url: "https://github.com/ordo-one/package-benchmark", .upToNextMajor(from: "1.29.11"))
]

#if os(Windows)
let products: [Product] = [
    .executable(name: "SwiftTermFuzz", targets: ["SwiftTermFuzz"]),
    .library(
        name: "SwiftTerm",
        targets: ["SwiftTerm"]
    ),
]

let targets: [Target] = [
    .target(
        name: "SwiftTerm",
        dependencies: [],
        path: "Sources/SwiftTerm",
        exclude: platformExcludes + ["Mac/README.md"]
//        swiftSettings: [
//            .unsafeFlags(["-enforce-exclusivity=none"])
//        ]
    ),
    .executableTarget (
        name: "SwiftTermFuzz",
        dependencies: ["SwiftTerm"],
        path: "Sources/SwiftTermFuzz"
    ),
    .testTarget(
        name: "SwiftTermTests",
        dependencies: ["SwiftTerm"],
        path: "Tests/SwiftTermTests"
    )
]
#else
let products: [Product] = libraryOnly ? [
    .library(name: "SwiftTerm", targets: ["SwiftTerm"]),
] : [
    .executable(name: "SwiftTermFuzz", targets: ["SwiftTermFuzz"]),
    .executable(name: "termcast", targets: ["Termcast"]),
    .library(
        name: "SwiftTerm",
        targets: ["SwiftTerm"]
    ),
]

let benchmarkTargets: [Target] = (isGitHubActions || disableBenchmark) ? [] : [
    .executableTarget(
        name: "SwiftTermBenchmarks",
        dependencies: [
            "SwiftTerm",
            .product(name: "Benchmark", package: "package-benchmark")
        ],
        path: "Benchmarks/SwiftTermBenchmarks",
        plugins: [
            .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
        ]
    )
]

let swiftTermTarget: Target = .target(
        name: "SwiftTerm",
        //
        // We can not use Swift Subprocess, because there is no way of configuring the child process to
        // be a controlling terminal, as it is posix-spawn based.
//        dependencies: [
//            .product(name: "Subprocess", package: "swift-subprocess", condition: .when(platforms: [.macOS, .linux]))
//        ],
        path: "Sources/SwiftTerm",
        // A library-only build is a cross-compile for Windows or Linux, but
        // the manifest is evaluated on the Mac, so `platformExcludes` would
        // keep the Apple folders: exclude them by the switch instead.
        exclude: (libraryOnly ? ["Apple", "Mac", "iOS"] : platformExcludes) + (libraryOnly ? [] : ["Mac/README.md"]),
        // VTG files live under Sources/SwiftTerm/VectorTerminalGraphics and are
        // discovered with the rest of the target sources.
        resources: libraryOnly ? [] : [
            .process("Apple/Metal/Shaders.metal")
        ]
//        swiftSettings: [
//            .unsafeFlags(["-enforce-exclusivity=none"])
//        ]
    )

let targets: [Target] = libraryOnly ? [swiftTermTarget] : [
    swiftTermTarget,
    .executableTarget (
        name: "SwiftTermFuzz",
        dependencies: ["SwiftTerm"],
        path: "Sources/SwiftTermFuzz"
    ),
    .executableTarget (
        name: "Termcast",
        dependencies: [
            "SwiftTerm",
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ],
        path: "Sources/Termcast"
    ),
    .testTarget(
        name: "SwiftTermTests",
        dependencies: ["SwiftTerm"],
        path: "Tests/SwiftTermTests"
    )
] + benchmarkTargets
#endif

let package = Package(
    name: "SwiftTerm",
    platforms: [
        .iOS(.v14),
        (disableBenchmark ? .macOS(.v11) : .macOS(.v13)),
        .tvOS(.v13),
        .visionOS(.v1)
    ],
    products: products,
    dependencies: libraryOnly ? [] : [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.3"),
    ] + benchmarkDependencies,
//        .package(url: "https://github.com/swiftlang/swift-subprocess", revision: "426790f3f24afa60b418450da0afaa20a8b3bdd4")
    targets: targets,
    swiftLanguageVersions: [.v5]
)
