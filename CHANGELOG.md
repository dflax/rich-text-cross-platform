# Changelog

All notable changes to this project are documented here. Format loosely follows [Keep a
Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/), with the
0.x caveat that a minor bump can still be breaking (see `docs/ROADMAP.md`'s Packaging section).

## [Unreleased]

### Added

- Real build step for the web package (`tsup`), producing a publishable ESM `dist/` with `.d.ts`
  declarations. `main`/`module`/`types`/`exports` repointed at it; `react`/`react-dom`/`quill`
  stay external peer dependencies, not bundled.
- `CONTRIBUTING.md`, issue templates (bug report, feature request), and a PR template.

### Fixed

- CI: runs on the `macos-26` hosted runner image instead of `macos-15` — every run had failed 9/9
  since the workflow was added, because `macos-15` boots an actual macOS 15.7.9 host against this
  package's macOS-26 floor. `xcode-version` pinned to `26.6.0` from a confirmed real green run.
  Also fixed an independent bug the same failed logs exposed: the iOS Simulator destination step's
  `$SIMULATOR_ID` came back empty in every run; it now fails fast instead of silently matching
  nothing.
- Stale docs: the SPM version pin (`from: "0.3.0"` → `"0.4.0"`, matching the already-tagged
  release) in README.md and both `docs/guides/getting-started-*.md`; `PROVENANCE.md`'s claim that
  macOS/`NSTextView` "has not yet been built" (false since `v0.3.0`); `docs/ROADMAP.md`'s CI
  section, which still said "not yet set up."

### Decided

- Public API frozen for 1.0 — see `docs/ROADMAP.md`'s Decided section for the exact frozen
  surface.
- Distribution stays one `Package.swift`, two products — no split.
- XcodeGen stays as the example app's project-generation tool.
- The SwiftUI `TextEditor()`-based editor path stays unported, with a specific reopening
  condition: revisit if/when Apple ships `TextEditor()` support for real list markers (the
  concrete dealbreaker that ruled it out originally), preferring a single cross-platform
  implementation over today's `UITextView`/`NSTextView` split if that ever lands.

## [0.4.0] - 2026-09-15

### Added

- visionOS support: `RichTextEditor` runs on visionOS via the same `UITextView`-backed
  implementation as iOS, with an ornament-based toolbar placement instead of docking to content.
  A separate multi-window sample app, `examples/visionos-demo`.
- Backend guides: CloudKit (verified by direct compilation against the real SDK), Supabase
  (including a real RLS-empty-result-ambiguity lesson), PowerSync (a worked offline-first sync
  example).
- SwiftData persistence tab in the example app; example app renamed
  `examples/rich-text-editor-demo` to reflect its genuine multiplatform scope.

### Fixed

- Example app: `project.yml`'s `CODE_SIGNING_ALLOWED: false` forced a permanently unsigned binary
  that blocked real device installs (Simulator/"My Mac" never caught it) — moved to an
  `xcodebuild` command-line override for CI instead.

## [0.3.0] - 2026-09-14

### Added

- A real macOS editor on `NSTextView` (TextKit 2) — same public API as iOS
  (`RichTextEditor`, `RichTextEditorModel`, `RichTextTextView`, `RichTextEditorConfiguration`,
  `RichTextImageUploading`, `ImageDownscaling`), sharing type names across platforms via
  mutually-exclusive `#if canImport` files.
- A real, generated multiplatform Xcode project for the example app (XcodeGen).
- The CI workflow itself (`.github/workflows/ci.yml`) — added here, but not actually passing
  until the `macos-26` fix under Unreleased above.

### Changed

- Consolidated to one `Package.swift`, two products (`RichTextCore`, `RichTextEditor`) — no
  separate "Mac" product.
- Scrubbed internal proof-point references and pre-extraction type names out of every doc comment
  in `Sources/`, `Tests/`, and the web package.

### Fixed

- The README Quick Start's SPM dependency pin (`from: "0.1.0"`) was broken — no `0.1.0` tag had
  ever been pushed. Fixed by tagging `v0.3.0` for real and pointing the Quick Start at it.

## [0.1.0-pre] - 2026-09-13

Initial extraction from the private `rich-text-poc` proof-of-concept (see `PROVENANCE.md`):
`RichTextCore` and `RichTextEditor` as standalone Swift packages, the web editor package,
integration guides, initial backend guidance (Postgres, MySQL, MongoDB, Firebase), and the iOS
sample app. Never tagged as `v0.1.0` — see `[0.3.0]` above.
