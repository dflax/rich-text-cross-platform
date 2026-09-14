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

**Status: early — see [`docs/ROADMAP.md`](docs/ROADMAP.md).** The Swift package is real, tested,
and builds; the web package, sample apps, and backend adapters beyond Postgres are scoped but not
all built yet. Don't point production traffic at this yet — see [`PROVENANCE.md`](PROVENANCE.md)
for exactly what's proven versus newly extracted.

## Scope, read carefully

- **Reading** a document (rendering a `Delta` read-only) is cross-platform today: iOS, iPadOS,
  and macOS via SwiftUI, plus the web.
- **Editing** a document natively is **iOS/iPadOS only** right now. The editor is built on
  `UITextView`/TextKit 2 for real hanging indent and non-selectable list markers — the two things
  a naive `AttributedString`-based approach cannot do (see `docs/ARCHITECTURE.md`). `UITextView`
  has no macOS equivalent; `NSTextView` is a related but distinct API surface this project has
  not yet built or tested against. If you need native rich-text *editing* on macOS today, this
  isn't there yet — track it in `docs/ROADMAP.md`.
  - Editing on the **web** is not iOS-gated at all — Quill runs anywhere a browser does. The web
    package is scoped (see `docs/ROADMAP.md`) but not yet built out in this repository.
- **Vocabulary is deliberately small**: bold, italic, underline, strikethrough, links, headers
  (two levels), bulleted/numbered lists, and images with alt text. No tables, no code blocks, no
  arbitrary colors or fonts, no nested lists. This is a feature, not a gap to be filled — see
  `docs/ARCHITECTURE.md`'s Vocabulary section for why a small, closed vocabulary is what makes
  the round-trip and cross-platform-consistency guarantees possible at all.

## What's in here

```
swift/    RichTextCore (Delta model, codec, vocabulary, image cache, sync reconciliation)
          RichTextEditor (the UITextView-backed editor + its SwiftUI wrapper)
web/      Quill-based editor package + example app (scoped, see docs/ROADMAP.md)
backends/ A real Postgres schema/migration; adapter guidance for other stores lives in docs/backends/
docs/     Architecture, integration guides, backend contract + per-store guidance, roadmap
examples/ Full sample apps per platform, showing different RichTextEditorConfiguration options
```

## Quick start — Swift

```swift
dependencies: [
    .package(url: "<this repo's URL once published>", from: "0.1.0")
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

## Building and testing this repo

`RichTextCore` is a plain cross-platform Swift package:

```
cd swift && swift test
```

`RichTextEditor` uses a real `UITextView` and can't be exercised by plain `swift test` on macOS —
it needs an iOS Simulator destination:

```
cd swift
xcodebuild test -scheme RichTextCrossPlatform-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Backend

This project defines a storage **contract** — a `Delta` JSON blob, a version/updated-at column
for conflict detection, and an object-key-based image reference that's resolved to a URL only at
read time — rather than shipping one backend's implementation of it as *the* answer.
[`backends/postgres/`](backends/postgres/) has a real, working schema. [`docs/backends/`](docs/backends/)
covers the same contract for MySQL, MongoDB, and Firebase.

## License

Not yet decided — see the maintainer before treating this as available under any specific terms.
A `LICENSE` file will replace this section once that's settled (MIT is the leading candidate).

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — why this is shaped the way it is
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — what's done, what's scoped, what's not started
- [`docs/guides/`](docs/guides/) — integration guides
- [`docs/backends/`](docs/backends/) — the storage contract and per-database guidance
- [`PROVENANCE.md`](PROVENANCE.md) — where this code came from and what changed on the way here
