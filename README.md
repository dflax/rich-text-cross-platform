# Rich Text Cross-Platform

A rich-text document system built on **Quill Delta JSON** as a single canonical storage format,
with a real native Swift editor (TextKit 2, not a bridged web view) and a web editor built on
[Quill](https://quilljs.com/) — sharing one document format and one small, explicit formatting
vocabulary, so a document authored on one platform renders identically on the other.

This exists because the usual alternatives are both bad fits for "edit rich text natively on
every platform, store it as clean structured data": Markdown loses structure a real editor needs
(list identity, header level, exact selection) the moment you round-trip it through a parser, and
a bridged web view for native editing gets you real text selection nowhere and no native image
handling. Quill Delta is a small, well-specified JSON format with the structure a real editor
needs and none of Markdown's ambiguity; this project's job is a matching pair of first-class
native editors around it, plus enough backend-agnostic contract that it isn't tied to one stack.

**Status: early, but editing is now real on all four Apple platforms, hands-on verified on real
Mac and iOS hardware.** The Swift package and the web package are both real and tested — 83
cross-platform `RichTextCore` tests, 4 iOS-only and 6 macOS-only `RichTextEditor` tests (against
real, attached `UITextView`/`NSTextView` instances), 22 web tests proven against the *same*
fixture corpus the Swift side uses. Beyond the test suite, the example app has been hands-on
verified on real Mac and iOS hardware (not just Simulator) — real typing, toolbar formatting, list
markers with correct hanging indent, rich paste from both Notes and Safari on macOS. visionOS
support is real too — the separate `examples/visionos-demo` app builds and runs on the visionOS
Simulator — but has only been checked there, not on real Vision Pro hardware. CI runs `swift test`,
an iOS Simulator suite, the example app's build, and the web package's tests on every push — see
[`.github/workflows/ci.yml`](.github/workflows/ci.yml). Not yet done: publishing the web package to
the npm registry (it has a real build step now, `npm run build`, just isn't published), and backend
adapters beyond a real Postgres schema are guidance rather than shipped code. Don't point
production traffic at this yet — see [`PROVENANCE.md`](PROVENANCE.md) for exactly what's proven
versus newly extracted, and [`docs/ROADMAP.md`](docs/ROADMAP.md) for the full punch list.

## Scope, read carefully

- **Reading** a document (rendering a `Delta` read-only) is cross-platform today: iOS, iPadOS,
  macOS, and visionOS via SwiftUI, plus the web.
- **Editing** a document natively works on **iOS, iPadOS, macOS, and visionOS.** One public API
  (`RichTextEditor`, `RichTextEditorModel`, `RichTextTextView` — the same type names on every
  platform) backed by `UITextView` on iOS/iPadOS/visionOS (visionOS shares UIKit with iOS, so this
  is the same implementation, unmodified) and `NSTextView` on macOS, both on TextKit 2, for real
  hanging indent and non-selectable list markers — the two things a naive `AttributedString`-based
  approach cannot do (see `docs/ARCHITECTURE.md`). On visionOS, the default toolbar places itself
  in a window ornament instead of docking to the content, matching that platform's own idiom for
  a persistent secondary control surface.
  - Editing on the **web** is not iOS-gated at all — Quill runs anywhere a browser does. The web
    package (`web/packages/rich-text-editor`) is real, tested, and built (`npm run build`
    produces a publishable `dist/`); see `docs/ROADMAP.md` for what's left (a sample app, wider
    test coverage, and publishing it to the npm registry).
- **Vocabulary is deliberately small**: bold, italic, underline, strikethrough, links, headers
  (two levels), bulleted/numbered lists, and images with alt text. No tables, no code blocks, no
  arbitrary colors or fonts, no nested lists. This is a feature, not a gap to be filled — see
  `docs/ARCHITECTURE.md`'s Vocabulary section for why a small, closed vocabulary is what makes
  the round-trip and cross-platform-consistency guarantees possible at all.

## What's in here

```
Package.swift  One Swift package, two products: RichTextCore (Delta model, codec, vocabulary,
               image cache, sync reconciliation) and RichTextEditor (the editor + its SwiftUI
               wrapper — UITextView-backed on iOS/iPadOS/visionOS, NSTextView-backed on macOS,
               same public type names on every platform via mutually-exclusive
               `#if canImport`/`#if os` files)
Sources/       RichTextCore/, RichTextEditor/ — see above
Tests/         RichTextCoreTests/, RichTextEditorTests/ (iOS- and macOS-specific suites, each
               gated to the platform they exercise)
web/           packages/rich-text-editor — the Quill-based editor package (real, tested)
fixtures/      The shared Delta corpus both platforms' tests are proven against
backends/      A real Postgres schema/migration; adapter guidance for other stores lives in docs/backends/
docs/          Architecture, integration guides, backend contract + per-store guidance, roadmap
examples/      A multiplatform (iOS/iPadOS/macOS) sample app, showing different configuration
               options (examples/rich-text-editor-demo/README.md), plus a separate visionOS
               sample app demonstrating multi-window editing (examples/visionos-demo/README.md)
```

## Quick start — Swift

One package, two products — add it once, pick which product(s) you need:

```swift
dependencies: [
    // v0.4.0 is a real, working tag — not 1.0, the public API can still move. `from: "0.4.0"`
    // resolves to `>=0.4.0, <0.5.0` (SPM's semver rule for 0.x versions treats a minor bump as
    // a potential breaking change, unlike after 1.0). Verified against the real tagged commit,
    // not assumed.
    .package(url: "https://github.com/dflax/rich-text-cross-platform", from: "0.4.0")
],
targets: [
    .target(name: "YourApp", dependencies: ["RichTextCore", "RichTextEditor"])
]
```

```swift
import RichTextCore
import RichTextEditor

struct NoteEditor: View {
    @State private var delta = Delta(ops: [.text("\n")])
    let imageStore: ImageStore

    var body: some View {
        RichTextEditor(delta: $delta, imageStore: imageStore)
    }
}
```

See [`docs/guides/getting-started-ios.md`](docs/guides/getting-started-ios.md) (iOS/iPadOS) or
[`docs/guides/getting-started-macos.md`](docs/guides/getting-started-macos.md) (macOS) for a
complete walkthrough including image upload wiring, and [`examples/`](examples/) for full sample
apps.

## Quick start — web

```
cd web/packages/rich-text-editor && npm install
```

```tsx
import { QuillHost, configureImageBaseURL, type Delta } from "@rich-text-cross-platform/editor";

configureImageBaseURL("https://your-bucket.example.com"); // once, at app startup

<QuillHost initialDelta={delta} onReady={(api) => { /* api.getDelta() / api.setDelta(d) */ }} />
```

See [`web/packages/rich-text-editor/README.md`](web/packages/rich-text-editor/README.md).

## Building and testing this repo

`RichTextCore` is plain cross-platform Swift, and `RichTextEditor`'s macOS half (a real
`NSTextView`) is native AppKit — both run with no simulator:

```
swift test
```

`RichTextEditor`'s iOS half uses a real `UITextView`, which plain `swift test` on macOS can't
exercise (that file is gated behind `#if canImport(UIKit)`, so it compiles to an empty module and
contributes 0 tests there). To run the iOS-specific suite too, use an iOS Simulator destination:

```
xcodebuild test -scheme RichTextCrossPlatform-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The same scheme also runs on a real macOS destination (`-destination 'platform=macOS'`), which is
how the macOS-only `RichTextEditorModel` suite gets exercised through Xcode instead of plain
`swift test`, identically to the iOS Simulator case above.

The web package is a plain Node/Vitest project:

```
cd web/packages/rich-text-editor
npm install && npm test && npm run typecheck
```

## Backend

This project defines a storage **contract** — a `Delta` JSON blob, a version/updated-at column
for conflict detection, and an object-key-based image reference that's resolved to a URL only at
read time — rather than shipping one backend's implementation of it as *the* answer.
[`backends/postgres/`](backends/postgres/) has a real, working schema. [`docs/backends/`](docs/backends/)
covers the same contract for MySQL, MongoDB, and Firebase.

## License

[MIT](LICENSE) — chosen specifically because it permits commercial use without restriction.

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — why this is shaped the way it is
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — what's done, what's scoped, what's not started
- [`docs/guides/`](docs/guides/) — integration guides
- [`docs/backends/`](docs/backends/) — the storage contract and per-database guidance
- [`PROVENANCE.md`](PROVENANCE.md) — where this code came from and what changed on the way here
- [`CHANGELOG.md`](CHANGELOG.md) — what changed in each release

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for how to build, test, and submit a change, plus the
issue and PR templates under [`.github/`](.github/). The public API is being frozen for a 1.0
release (see `docs/ROADMAP.md`'s Decided section for the exact surface), but that tag hasn't
landed yet — until it does, treat the API as still capable of moving.
