// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RichTextEditor",
    // iOS/iPadOS only — a real UITextView, no macOS equivalent (NSTextView is a related but
    // distinct API surface this project hasn't built against yet; see README.md's Scope
    // section). This means plain `swift test` here fails on macOS: it always builds the whole
    // package, and this target imports UIKit unconditionally. Test via Xcode against an iOS
    // Simulator destination instead — see README.md.
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "RichTextEditor", targets: ["RichTextEditor"])
    ],
    dependencies: [
        .package(path: "../RichTextCore")
    ],
    targets: [
        .target(name: "RichTextEditor", dependencies: ["RichTextCore"]),
        .testTarget(name: "RichTextEditorTests", dependencies: ["RichTextEditor"]),
    ]
)
