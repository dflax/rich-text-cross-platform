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

**Status: early.** The Swift package and the web package are both real and tested — 87 Swift
tests, 22 web tests, the web tests proven against the *same* fixture corpus the Swift side uses,
which is the actual cross-platform-consistency proof, not just a claim. Not yet done: a native
macOS editor (in progress — see `docs/ROADMAP.md`), sample apps aren't fully wired into runnable
projects yet, the web package has no build step for publishing, and backend adapters beyond a
real Postgres schema are guidance, not shipped code. Don't point production traffic at this yet —
see [`PROVENANCE.md`](PROVENANCE.md) for exactly what's proven versus newly extracted, and
[`docs/ROADMAP.md`](docs/ROADMAP.md) for the full punch list.

## Scope, read carefully

- **Reading** a document (rendering a `Delta` read-only) is cross-platform today: iOS, iPadOS,
  and macOS via SwiftUI, plus the web.
- **Editing** a document natively is **iOS/iPadOS only** right now. The editor is built on
  `UITextView`/TextKit 2 for real hanging indent and non-selectable list markers — the two things
  a naive `AttributedString`-based approach cannot do (see `docs/ARCHITECTURE.md`). A native
  macOS editor on `NSTextView` is committed, in-progress work, not a maybe — see
  `docs/ROADMAP.md` for status.
  - Editing on the **web** is not iOS-gated at all — Quill runs anywhere a browser does. The web
    package (`web/packages/rich-text-editor`) is real and tested; see `docs/ROADMAP.md` for what's
    left (a build step, a sample app, wider test coverage).
- **Vocabulary is deliberately small**: bold, italic, underline, strikethrough, links, headers
  (two levels), bulleted/numbered lists, and images with alt text. No tables, no code blocks, no
  arbitrary colors or fonts, no nested lists. This is a feature, not a gap to be filled — see
  `docs/ARCHITECTURE.md`'s Vocabulary section for why a small, closed vocabulary is what makes
  the round-trip and cross-platform-consistency guarantees possible at all.

## What's in here

```
Package.swift  One Swift package, two products: RichTextCore (Delta model, codec, vocabulary,
               image cache, sync reconciliation) and RichTextEditor (the UITextView-backed
               editor + its SwiftUI wrapper)
Sources/       RichTextCore/, RichTextEditor/ — see above
Tests/         RichTextCoreTests/, RichTextEditorTests/
web/           packages/rich-text-editor — the Quill-based editor package (real, tested)
fixtures/      The shared Delta corpus both platforms' tests are proven against
backends/      A real Postgres schema/migration; adapter guidance for other stores lives in docs/backends/
docs/          Architecture, integration guides, backend contract + per-store guidance, roadmap
examples/      Sample apps per platform, showing different configuration options (see docs/ROADMAP.md)
```

## Quick start — Swift

One package, two products — add it once, pick which product(s) you need:

```swift
dependencies: [
    // No tagged release yet — pin to `branch: "main"` until v0.1.0 is cut, then switch to
    // `from: "0.1.0"`. Verified: `from:` fails to resolve today with no tags pushed.
    .package(url: "https://github.com/dflax/rich-text-cross-platform", branch: "main")
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

See [`docs/guides/getting-started-ios.md`](docs/guides/getting-started-ios.md) for a complete
walkthrough including image upload wiring, and [`examples/`](examples/) for full sample apps.

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

`RichTextCore` is plain cross-platform Swift — the whole suite runs with no simulator:

```
swift test
```

`RichTextEditor` uses a real `UITextView` and can't be exercised by plain `swift test` on macOS
(its source is gated behind `#if canImport(UIKit)`, so `swift test` still succeeds — it just
compiles that product to an empty module and runs 0 of its tests). To run everything, including
`RichTextEditor`'s own tests, use an iOS Simulator destination:

```
xcodebuild test -scheme RichTextCrossPlatform-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

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

## Contributing

Not formally set up yet (no `CONTRIBUTING.md`, no issue templates — see `docs/ROADMAP.md`), but
issues and PRs are welcome. This is early: expect the public API to move.
