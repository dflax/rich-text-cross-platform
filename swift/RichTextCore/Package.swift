// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RichTextCore",
    // Cross-platform on purpose — this is the Delta model, codec, vocabulary, image cache, and
    // sync reconciliation, none of which touch UIKit. Kept as its own package, separate from
    // RichTextEditor (iOS/iPadOS only, real UITextView), specifically so `swift test` here stays
    // fast and simulator-free — see README.md.
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "RichTextCore", targets: ["RichTextCore"])
    ],
    targets: [
        .target(name: "RichTextCore"),
        .testTarget(
            name: "RichTextCoreTests",
            dependencies: ["RichTextCore"],
            resources: [.copy("Resources/fixtures")]
        ),
    ]
)
