// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RichTextCrossPlatform",
    // One manifest, multiple products, so a consumer adds a single remote dependency and picks
    // whichever products they need via `.product(name:, package:)` — see README.md's Quick
    // Start and docs/ROADMAP.md's "Decided" section for why this replaced two separate
    // packages. RichTextEditor now has a real implementation on both iOS/iPadOS (`UITextView`)
    // and macOS (`NSTextView`), sharing the same public type names via mutually-exclusive
    // `#if canImport(UIKit)`/`#if canImport(AppKit)` files — see docs/ARCHITECTURE.md's macOS
    // section. The platform guard is still what lets `swift build`/`swift test` succeed
    // everywhere despite SPM having no per-target platform-restriction mechanism (it always
    // attempts every target regardless of the current platform): on macOS the iOS-only files
    // compile to a harmless empty module instead of failing on an unconditional `import UIKit`,
    // and vice versa for AppKit-only files on iOS. Confirmed empirically, not assumed.
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "RichTextCore", targets: ["RichTextCore"]),
        .library(name: "RichTextEditor", targets: ["RichTextEditor"]),
    ],
    targets: [
        .target(name: "RichTextCore"),
        .testTarget(
            name: "RichTextCoreTests",
            dependencies: ["RichTextCore"],
            resources: [.copy("Resources/fixtures")]
        ),

        .target(name: "RichTextEditor", dependencies: ["RichTextCore"]),
        .testTarget(name: "RichTextEditorTests", dependencies: ["RichTextEditor"]),
    ]
)
