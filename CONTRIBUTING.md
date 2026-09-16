# Contributing

Thanks for considering a contribution. This project is early — see [`README.md`](README.md) for
scope and status, [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for why it's shaped the way it
is, and [`docs/ROADMAP.md`](docs/ROADMAP.md) for what's done, what's scoped but not built, and
what's decided. Read `docs/ROADMAP.md` before opening a PR for anything nontrivial — it's kept
current on purpose and is the actual source of truth for what's left, not this file.

## Before you start

- **The formatting vocabulary is deliberately small and closed** — bold, italic, underline,
  strikethrough, links, two header levels, bulleted/numbered lists, images with alt text. No
  tables, no code blocks, no arbitrary colors or fonts, no nested lists. This isn't an oversight;
  see `docs/ARCHITECTURE.md`'s Vocabulary section for why a small, closed vocabulary is what makes
  the round-trip and cross-platform-consistency guarantees possible at all. A PR adding a new
  format needs a design discussion first (open an issue), not just an implementation.
- **The public API is being frozen for 1.0** — see `docs/ROADMAP.md`'s Decided section for the
  exact frozen surface and current status. A PR that changes a public type's shape on either
  platform (Swift or the web package) needs to account for that, not just pass its own tests.
- Check `docs/ROADMAP.md`'s "Scoped, not yet built" section for known gaps before starting
  something new — it's ordered by what unblocks the most other work, and saves you from duplicating
  something already planned a specific way.

## Building and testing

Swift side, from the repo root:

```
swift test
```

exercises `RichTextCore` (cross-platform) and `RichTextEditor`'s macOS half (real `NSTextView`) —
no simulator needed. For the iOS half (real `UITextView`, gated behind `#if canImport(UIKit)` and
invisible to plain `swift test` on macOS):

```
xcodebuild test -scheme RichTextCrossPlatform-Package \
  -destination 'platform=iOS Simulator,name=<a booted-capable simulator>'
```

The same scheme also runs on `-destination 'platform=macOS'`, which is how the macOS-only
`RichTextEditorModel` suite gets exercised through Xcode instead of plain `swift test`.

Web package:

```
cd web/packages/rich-text-editor
npm install && npm test && npm run typecheck && npm run build
```

CI (`.github/workflows/ci.yml`) runs all of the above, plus the example app's build, on every push
and PR to `main` — check that it's green before asking for review, not just that your local run
passed.

## Submitting a change

1. Fork the repo and branch off `main`.
2. Make your change. If it touches `#if canImport(UIKit)` or `#if canImport(AppKit)` gated code,
   verify both platforms build — a clean compile on one says nothing about the other. SPM has no
   target-level platform restriction, so `swift build`/`swift test` always attempt every target
   regardless of host platform; a UIKit-only file needs its *entire* contents guarded (first line
   `#if canImport(UIKit)`, last line `#endif`), not just its `import UIKit` line, or it'll fail to
   compile on macOS.
3. Open a PR against `main`. Describe *why*, not just *what* — this repo's own commit history and
   `docs/ROADMAP.md` favor recording the reasoning behind a change, not just the diff.
4. Wait for CI to go green. A maintainer will review from there.

## Reporting bugs / requesting features

Use the issue templates. For a bug, include exact repro steps and, if it's platform-specific,
which platform(s) you saw it on and haven't. For a feature request, check the vocabulary note
above first — most format-related requests are a scope question, not an implementation gap.

## License

By contributing, you agree your contribution is licensed under this project's [MIT
license](LICENSE).
