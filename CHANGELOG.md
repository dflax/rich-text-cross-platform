# Changelog

All notable changes to this project are documented here. Format loosely follows [Keep a
Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/), with the
0.x caveat that a minor bump can still be breaking (see `docs/ROADMAP.md`'s Packaging section).

## [Unreleased]

## [0.4.6] - 2026-09-17

### Fixed

- `ReadLayout.groups(from:)`: a wrapped multi-line bullet/numbered list item read correctly in the
  edit view (real hanging indent, via TextKit's `NSTextList`) but wrapped flush under the marker in
  the read view — found by hands-on device testing, confirmed to reproduce on iOS and confirmed
  absent on web (Quill's own CSS handles this correctly there). Root cause: the read path bakes the
  marker into plain characters (so the whole span can live in one selectable run — see this file's
  own doc comment) but never attached a hanging-indent `.paragraphStyle`, unlike the edit path.
  Fixed by attaching the same `headIndent = 28` / `firstLineHeadIndent = 0` the edit path already
  uses (`NSDeltaCodec.applyVisualBlockStyling`), scoped to exactly the list line's own characters
  and its own trailing newline — never bleeding onto an adjacent non-list line. Deliberately does
  NOT set `textLists` (the marker is already literal text here; a renderer that also honored
  `textLists` would draw it twice).
  **Known limitation, not fixed at this layer**: SwiftUI's `Text(AttributedString)` silently
  ignores `.paragraphStyle` entirely — confirmed by direct measurement (an `NSHostingView` wrapping
  an indented vs. non-indented `Text` at the same fixed width produced byte-identical fitting
  heights), so a host rendering `.text` groups via plain `Text` still won't see this fix visually.
  A host needs a real TextKit-backed renderer (`UITextView`/`NSTextView`, `isEditable = false`,
  `isSelectable = true`) to see the corrected indent — see `docs/guides/read-only-rendering.md`.

## [0.4.5] - 2026-09-17

### Changed

- iOS: the format toolbar now docks to the keyboard via `UITextView.inputAccessoryView`
  (`RichTextEditorUITextView`) instead of a SwiftUI `.safeAreaInset(edge: .bottom)` toolbar. Real
  hands-on device testing found the `.safeAreaInset` toolbar stayed pinned to the bottom of the
  text view's own (auto-growing) frame rather than the keyboard on anything longer than a
  screenful, forcing a scroll to reach it on a long document. Two separate attempts at fixing that
  by moving `RichTextEditor` into its own full-screen `.sheet` both broke on an unrelated SwiftUI
  bug instead (a `.sheet` nested inside another sheet's own `NavigationStack` collapsing the whole
  presentation stack — confirmed via live console streaming to not be a crash). `inputAccessoryView`
  sidesteps that class of problem entirely: UIKit positions it against the keyboard directly,
  independent of whatever ScrollView/Form/sheet structure the host embeds this editor in — inline
  or full-screen, sheet-nested or not. macOS (`.safeAreaInset`, no software keyboard) and visionOS
  (`.ornament`) are unaffected.

## [0.4.4] - 2026-09-17

### Added

- `RichTextEditorConfiguration.showsUnsavedIndicator` (default `true`, matching prior behavior) —
  a host with its own formal Save/Create button (no auto-save) found the default gray "Unsaved"
  pill (shown whenever `model.isDirty`) read as a false alarm: every normal keystroke briefly
  showed it even though the host's own explicit save path was always going to pick up the change
  regardless of timing. Set `false` to suppress it for that kind of host.

## [0.4.3] - 2026-09-17

### Fixed

- `RichTextEditor`'s plain `.task { await load() }` was observed, via real hands-on device
  testing (not simulator - this never surfaced there), to actually fire a second time after the
  editor was already loaded and live. That second firing created a SECOND `RichTextEditorModel`,
  replacing the view's `model` state - and therefore what the toolbar and `onModelReady` (below)
  operate on - while `RichTextTextView`'s own `UIViewRepresentable`/coordinator, whose identity
  SwiftUI preserved across the re-render, stayed attached to the FIRST, now-orphaned model. Typing
  kept working (native `UITextView` behavior, independent of the model), but every toolbar action
  - bold, italic, lists, links - and every save silently no-opped, because they all ran on the
  second model, whose `textView` was never attached to anything. `load()` now guards against
  re-entry with a flag set synchronously before its `await`, so a second firing (or two
  near-simultaneous ones) can't create a competing model. Not unit-testable at this layer without
  new SwiftUI-view-testing infrastructure this package doesn't have yet (its own test suite
  exercises `RichTextEditorModel` directly, bypassing `UIViewRepresentable` entirely) - verified
  via real device testing with temporary diagnostic logging, confirming the same `UITextView`
  stayed attached to the same model across load, typing, formatting, and save.

## [0.4.2] - 2026-09-17

### Added

- `RichTextEditor.onModelReady: ((RichTextEditorModel) -> Void)?` — an optional init parameter,
  called once as soon as the model finishes loading. Fills the one real gap `docs/guides/
  saving.md`'s "if you can't use `onDone`" branch left open: that guide says a host with its own
  Save/Create button should "read `delta`'s current value" before persisting, but without a
  handle to the live model there was no way to force that value to be current first. A host now
  captures the model here and, right before reading the `delta` binding, calls
  `model.encodeIfChanged()` then re-reads `model.savedDelta` — genuinely synchronous, since
  `encodeIfChanged()` reads straight from the live `UITextView.textStorage` and cancels the
  pending debounce itself rather than waiting on it.

## [0.4.1] - 2026-09-16

Tagged retroactively while writing this entry — the `[Unreleased]` heading above these entries was
never cut over when `v0.4.1` was actually tagged. Content unchanged, just correctly dated now.

### Fixed

- `ImageDownscaler` failed outright on a HEIC photo picked via `PhotosPicker` on iOS (HEIC has
  been the default Photos-library capture format since iOS 11) — surfaced to the user as "Could
  not re-encode the picked image," found via real hands-on device testing, not a simulator. The
  previous implementation decoded via `UIImage(data:)`/`NSImage(data:)` plus a manual redraw;
  rewritten on `CGImageSource`/`CGImageDestination` (ImageIO) instead, which handles HEIC/HEIF
  (and everything else ImageIO supports) directly, bakes in EXIF orientation correctly via
  `kCGImageSourceCreateThumbnailWithTransform`, and removes the `#if os(macOS)` split this
  function used to need entirely — one implementation for both platforms now.
- `RichTextEditor`: tapping linked text opened the URL instead of placing a cursor there, even
  though the text view is editable — `UITextView`'s default behavior activates a `.link`
  attribute on a single tap regardless of `isEditable`. The only way to get a cursor inside a
  link's text was iOS's keyboard-trackpad cursor-drag gesture. Fixed by returning `false` for
  `.invokeDefaultAction` in `shouldInteractWith`; `.presentActions` (long-press) still returns
  `true`, so the system's Open/Copy Link menu remains available — a link is fully usable, just
  not activated by accident on a plain tap, matching Notes.app/Mail's own editable-link behavior.
- `RichTextEditor`'s horizontal margins (16pt each side) read as too wide on a phone-width screen
  in real hands-on testing — halved to 8pt; vertical padding is unchanged.
- Web package: a HEIC photo pasted from Notes.app on macOS (or any paste where Quill's own image
  matching can't resolve the `<img>` to a string — observed with a browser `blob:` URL src) could
  produce a non-string image embed (`{"insert":{"image":true}}`) that the strict decoder rejects,
  surfacing as `Op N's "insert" is neither a string nor an embed object.` and blocking every save
  until the offending content was manually deleted. Fixed by `installPasteGuards` above, which
  intercepts every pasted image before Quill's own matching runs, regardless of what that matching
  would have produced.
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
