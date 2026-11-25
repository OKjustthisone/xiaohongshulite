// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RedNoteLite",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "RedNoteLite", targets: ["RedNoteLite"])
    ],
    targets: [
        .target(
            name: "RedNoteCore",
            path: "Sources/RedNoteCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "RedNoteLite",
            dependencies: ["RedNoteCore"],
            path: "Sources/RedNoteLite",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "RedNoteCoreTests",
            dependencies: ["RedNoteCore"],
            path: "Tests/RedNoteCoreTests"
        )
    ]
)
