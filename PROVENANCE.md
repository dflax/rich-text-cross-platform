# Provenance

This project began as an extraction from a private proof-of-concept repository
(`rich-text-poc`), not a from-scratch design. Recording where it came from and what changed in
the move, so a bug that looks new here can be checked against whether it's actually new.

## Fork point

Extracted from `rich-text-poc` at commit `5b9f22fd556ccfd16d018aa4f6a5b0d227a45ee3` (2026-09-13).
That repository explored two parallel rich-text editor implementations for iOS/iPadOS/macOS —
one built on SwiftUI's `TextEditor(text:selection:)`, one built directly on `UITextView` — as a
deliberate side-by-side comparison, plus a web client using Quill. The UIKit-based editor won
that comparison (see the POC's own `docs/PRD-uikit-comparison-editor.md` for the reasoning); this
project carries that implementation forward as a real, reusable component. The SwiftUI/
`TextEditor`-based path, and the literal-marker-injection workaround it needed
(`ListMarkerSync`), were not ported — see below.

## What was ported as-is

`swift/Sources/RichTextCore/` — Delta value types, vocabulary enforcement, the
`NSAttributedString` codec (`NSDeltaCodec`), read-only rendering, the offline-safe image cache
(`ImageStore`), and three-way sync reconciliation. This is the POC's own `RichTextCore` Swift
package, unchanged in logic. Three adjustments for standalone use:

- The fixture corpus moved from a repo-root-relative path (the POC's tests located it by walking
  up from `#filePath` to a sibling `fixtures/` directory, since it was also shared with the POC's
  web client at a known path) into a proper SPM test-target resource bundle
  (`Tests/RichTextCoreTests/Resources/fixtures`, loaded via `Bundle.module`). A standalone package
  can't assume anything about what sits above it in a consumer's checkout.
- `BlockToken` — previously defined alongside the (excluded) SwiftUI-specific `DeltaCodec`, since
  that's where it was first needed — moved into `Delta.swift`, since it's a plain value type both
  the excluded codec and the ported one depend on, and belongs with the other value types.
- `B2PublicImageFetcher` renamed `PublicURLImageFetcher`, doc comment genericized. It never had
  any B2-specific logic — it's a plain "GET `baseURL` + key over HTTP" fetcher — and Backblaze B2
  was only ever the POC's own deployment choice, not something the type itself should imply.

## What was extracted and rewritten

`swift/Sources/RichTextEditor/` — the POC's `UIKitEditorModel`/`UITextViewRepresentable`/
`NotesFormatBar` (renamed `RichTextEditorModel`/`RichTextTextView`/`RichTextFormatBar`), which
turned out to already have zero direct coupling to the POC's backend services — that coupling
lived entirely in the SwiftUI view that hosted them (`UIKitDocumentEditorView`), not in the
editor model itself. That host view was not ported; a new one, `RichTextEditor` (the public SwiftUI
entry point), was written to take a plain `Binding<Delta>`, an `ImageStore`, and an optional
`RichTextImageUploading` protocol conformance instead of the POC's `AppServices`/`FixtureLibrary`-
specific plumbing. See `docs/ARCHITECTURE.md` for the resulting shape.

## What was deliberately not ported

- `DeltaCodec.swift`, `Segmentation.swift`, `ListMarkerSync.swift`, `FormattingDefinition.swift` —
  the SwiftUI `TextEditor`/`AttributedString`-based editor path and its literal-marker-injection
  workaround. Porting both editor implementations would double the public API surface of
  something meant to be a tight, single-purpose component. If SwiftUI's own text editing APIs
  close the gap that motivated building on UIKit in the first place, that's worth revisiting —
  see `docs/ROADMAP.md`.
- `ImageStoreLiveTests.swift` — an opt-in test hardcoded to the POC's own throwaway Backblaze B2
  bucket and a specific object key that only exists there. Not meaningful outside that bucket.
- Everything backend-specific: the POC's Supabase-schema sync engine, SwiftData caching layer,
  and B2 upload client. This project defines the storage *contract* (see `docs/backends/`) rather
  than shipping one backend's implementation of it.

## Known gap carried forward, not introduced here

The editor is iOS/iPadOS only — `UITextView` has no macOS equivalent; `NSTextView` is a related
but distinct API surface this project has not yet built or tested against. The POC's own PRD
named this gap explicitly rather than letting a strong iOS result imply a macOS answer nobody
checked; same posture here. See `README.md`'s Scope section and `docs/ROADMAP.md`.
