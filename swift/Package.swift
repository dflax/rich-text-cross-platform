// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RichTextCrossPlatform",
    // Matches the fork point's proven baseline (see PROVENANCE.md) rather than the lowest
    // target that might work: RichTextEditor's default toolbar uses the Liquid Glass API
    // (iOS 26+), and TextKit-2-on-UITextView compatibility below iOS 26 has not been verified
    // by this project, only assumed. Lowering this is real, worthwhile follow-up work — see
    // docs/ROADMAP.md — but should happen after verifying on the actual older OS, not by
    // guessing a number here.
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "RichTextCore", targets: ["RichTextCore"]),
        .library(name: "RichTextEditor", targets: ["RichTextEditor"]),
    ],
    targets: [
        // Delta model, vocabulary enforcement, the NSAttributedString codec, read-side
        // rendering, image caching, and sync reconciliation — no UI. Builds and runs its full
        // test suite on macOS alone; nothing here requires a simulator or a device.
        .target(name: "RichTextCore"),
        .testTarget(
            name: "RichTextCoreTests",
            dependencies: ["RichTextCore"],
            resources: [.copy("Resources/fixtures")]
        ),

        // The UITextView-backed editor and its SwiftUI wrapper. iOS/iPadOS only for now — see
        // README.md's Scope section for why, and PROVENANCE.md for what this was extracted from.
        .target(name: "RichTextEditor", dependencies: ["RichTextCore"]),
        .testTarget(name: "RichTextEditorTests", dependencies: ["RichTextEditor"]),
    ]
)
