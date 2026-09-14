// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RichTextCrossPlatform",
    // One manifest, multiple products, so a consumer adds a single remote dependency and picks
    // whichever products they need via `.product(name:, package:)` — see README.md's Quick
    // Start and docs/ROADMAP.md's "Decided" section for why this replaced two separate
    // packages. RichTextEditor is iOS/iPadOS only in practice (a real UITextView) but its source
    // is guarded with `#if canImport(UIKit)` rather than excluded from the manifest — SPM has no
    // per-target platform-restriction mechanism, so `swift build`/`swift test` always attempt to
    // build every target regardless of the current platform; the guard is what lets that attempt
    // succeed (as a harmless empty module) on macOS instead of failing outright on an
    // unconditional `import UIKit`. Confirmed empirically, not assumed.
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
