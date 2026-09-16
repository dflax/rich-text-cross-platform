# Architecture

## The format: Quill Delta

A document is a `Delta` — a flat sequence of `insert` operations, each optionally carrying
attributes (`{"insert": "bold text", "attributes": {"bold": true}}`). Block-level structure
(headers, lists) is carried as an attribute on the newline character that ends a line, not as a
nested tree — `{"insert": "\n", "attributes": {"header": 1}}` means "the line that just ended is
a Header 1." This is Quill's own format, not a modification of it: a canonical, well-specified
line-oriented model that a native client can encode/decode without needing Quill itself.

Two properties of the format are load-bearing for everything built on top of it:

- **It's flat, not a tree.** A native renderer walks operations in order; there's no nested
  document structure to reconcile between platforms.
- **Block attributes are metadata, restored verbatim — never inferred from rendering.** A
  header's larger font size, a list's marker glyph, are *derived from* the `header`/`list`
  attribute on decode; encode reads the attribute back, never guesses it from a font size it
  finds on a run. Get this backwards and a document silently degrades on a round trip — a header
  that happens to render at a size close to a bold run's could re-encode as bold text, not a
  header. See `RichTextCore/NSDeltaCodec.swift`'s own doc comments and `Vocabulary.swift`.

## The vocabulary is small and closed on purpose

`bold`, `italic`, `underline`, `strike`, `link`, `header` (1–2), `list` (bullet/ordered), and an
`image` embed with `alt` text — that's the whole authorable surface. Two consequences follow
directly from keeping it this small:

1. **Round-trip correctness is checkable, not just hoped for.** `encode(decode(d)) == d`,
   byte-identical, is a property test that actually passes for every document in the vocabulary
   — see `RichTextCoreTests`'s round-trip suite. A larger vocabulary (arbitrary colors, nested
   lists, tables) multiplies the edge cases that property test has to hold across.
2. **Every editor enforces the same boundary the same way**: never let an attribute outside this
   set reach the buffer, whether from the system's own format UI, a paste from another app, or a
   programmatic mutation. `RichTextCore/NSDeltaCodec.swift`'s `sanitizedForPaste`/
   `clampToVocabulary` are the UIKit editor's two layers of this — see
   `docs/guides/vocabulary-enforcement.md`.

## Why a real `UITextView`, not `AttributedString` + `TextEditor`

SwiftUI's `TextEditor(text:selection:)` is, as of recent SDKs, bound to a real `AttributedString`
rather than a plain `String` — genuinely new, and the obvious first thing to try. It has two
structural gaps that aren't implementation details to work around, they're properties of how
`TextEditor` renders:

- **No hanging indent.** A wrapped continuation line of a list item falls back to the left
  margin under the bullet instead of aligning under the item's text. `AttributedString` can
  technically carry a paragraph-style attribute (`AttributeScopes.UIKitAttributes.paragraphStyle`
  exists) — the gap is that `TextEditor` does not *render* it.
- **No non-selectable markers.** A real editor's bullet or number is a rendered decoration, not
  part of the text buffer a user can select into or backspace through character-by-character.
  There's no public SwiftUI API to mark a subrange of `TextEditor`'s content as present but
  unselectable — the only fallback is a literal marker character living in the buffer, which is
  then selectable/backspaceable/damageable by construction, and needs its own reconciliation
  pass to detect and repair damage (the approach this project's fork point took before this
  extraction, and deliberately did not carry forward — see `PROVENANCE.md`).

`UITextView` on TextKit 2 does both natively: `NSParagraphStyle.headIndent`/`firstLineHeadIndent`
and `NSTextList` are long-established mechanisms for exactly this, rendered as true decorations
never present in the editable string. The cost is real too, named rather than glossed over:

- **TextKit 2 must be verified, not assumed.** `UITextView` silently falls back to TextKit 1 the
  moment anything touches its legacy `layoutManager` property — no error, just wrong rendering.
  `RichTextTextView` asserts `textLayoutManager != nil` once the view is configured.
- **The binding loop must never do `uiView.attributedText = newValue`.** That resets selection
  and scroll position on every SwiftUI update pass — the UIKit-side version of the exact bug
  class that makes `TextEditor`'s own binding hazardous. `RichTextEditorModel` holds no separate
  document copy; `UITextView.textStorage` *is* the document while editing, mutated in place
  through `NSTextStorage`'s own methods.
- **Formatting-constraint enforcement has no declarative API on this path.**
  `AttributedTextFormattingDefinition` is SwiftUI-only. UIKit's enforcement is imperative:
  `allowsEditingTextAttributes = false` closes off the system's own format UI, and paste
  interception + an `NSTextStorageDelegate` backstop close off the realistic remaining vector —
  see `docs/guides/vocabulary-enforcement.md`.
## macOS: a genuinely separate implementation behind the same public API

`NSTextView` is AppKit's related but distinct API surface, not a drop-in `UITextView` — the real
editor on it (`RichTextEditorModel`, `RichTextTextView`, both in `...Mac.swift` files gated
`#if canImport(AppKit)`) shares its *public type names* with the iOS implementation but not a
line of its actual code, matching the pattern `RichTextCore` already established with
`PlatformFont`/`PlatformImage`/`PlatformColor`. A consumer writes `RichTextEditor(delta:
imageStore:)` once; which concrete class backs `RichTextEditorModel` is decided per-platform at
compile time, invisibly. Two design differences from the iOS model, both deliberate:

- **Selection collapses to `selectedRanges.first`.** `NSTextView` has no single-range property
  the way `UITextView` does — `selectedRanges: [NSValue]` exists because AppKit supports
  discontiguous multi-range selection, which this editor's vocabulary and toolbar don't use on
  either platform. Collapsing here matches the iOS UX exactly rather than threading multi-range
  selection through code that was never designed around it.
- **No `NSScrollView`.** `NSTextView` has no `isScrollEnabled` — the auto-growing-height trick
  `RichTextTextView` uses on iOS has an AppKit equivalent, not an identical API: the text
  container tracks the view's own width with unbounded height, and `intrinsicContentSize` is
  derived from `NSTextLayoutManager.usageBoundsForTextContainer`.

Three real, non-obvious bugs surfaced only by actually launching the editor — `swift build`
compiling cleanly proved nothing about any of them, which is itself worth remembering next time
AppKit text is on the critical path:

- **TextKit 2 is not the AppKit default.** `UITextView()` defaults to TextKit 2; the AppKit
  equivalent, plain `NSTextView()`, silently defaults to legacy TextKit 1. The explicit opt-in is
  a different initializer, `NSTextView(usingTextLayoutManager: true)`.
- **Reading the legacy `.layoutManager` property — even just once, even read-only — permanently
  downgrades that view to TextKit 1 compatibility mode, silently, no error.** This is a stricter
  trap than UIKit's "don't touch it" rule implies: an `intrinsicContentSize` override written by
  direct analogy to the iOS one (`layoutManager.usedRect(for:)`) reintroduces exactly the failure
  the `usingTextLayoutManager: true` opt-in was supposed to prevent. The TextKit-2-native
  replacement is `NSTextLayoutManager.usageBoundsForTextContainer`, never `.layoutManager`.
- **`NSViewRepresentable.updateNSView` is not a reliable enough signal for "the view now has a
  window."** Unlike `UIViewRepresentable` on iOS (where the analogous timing issue is solved by
  deferring the TextKit-2 assertion into `didMoveToWindow`), an `NSTextView` that should start
  focused could stay unfocused indefinitely here, because nothing guarantees SwiftUI calls
  `updateNSView` again once attachment actually completes if the `focused` binding's *value*
  never changes in between. Establishing first responder status inside `NSView.viewDidMoveToWindow`
  — not `updateNSView` — is the fix, mirroring where `RichTextEditorUITextView` already checks
  its own window-dependent state for an unrelated reason (dynamic color resolution).

All three were caught by actually launching the packaged example app on a real Mac and typing
into it — not by `swift build`, `swift test`, or code review — which is the concrete case for why
`examples/ios-basic`'s Xcode project builds for macOS as a first-class destination rather than
existing only for iOS.

## visionOS: the same UIKit implementation, a different toolbar placement

visionOS is not a third text-editing implementation the way macOS is — it shares UIKit with iOS,
so `RichTextCore`, `RichTextEditorModel`, and `RichTextTextView` (all backed by `UITextView` and
TextKit 2) type-check and run unmodified. There is no `...Vision.swift` file anywhere in this
package; visionOS takes the exact same `#if canImport(UIKit)` branch iOS already does. Confirmed
by direct compilation against the real visionOS SDK
(`xcrun --sdk xrsimulator swiftc -target arm64-apple-xros26.0-simulator`), not inferred from "it's
UIKit-based" as an assumption — see `docs/visionos.md` for the full assessment this was based on.

The one thing that doesn't carry over unmodified is `RichTextFormatBar`'s chrome and placement:

- **Liquid Glass has no visionOS equivalent API — because visionOS doesn't need the same opt-in.**
  `GlassEffectContainer` and `.glassEffect(in:)` are both `@available(visionOS, unavailable)`;
  visionOS's own materials system is built into the compositor, and its API for the same effect is
  `.glassBackgroundEffect(in:)` with no container wrapper needed. `RichTextFormatBar.swift` branches
  on `#if os(visionOS)` for both call sites (the bar's capsule and the `Aa` panel's rounded
  rectangle) plus the outer `GlassEffectContainer`/`Group` wrapper — a one-file, platform-
  conditional swap, not a rewrite.
- **The toolbar lives in a window ornament, not `.safeAreaInset(edge: .bottom)`.** A floating bar
  docked above the keyboard is an iOS idiom that assumes a keyboard and a phone-sized content
  area; visionOS's own idiom for a persistent, secondary control surface attached to a window is
  an ornament (`.ornament(attachmentAnchor:contentAlignment:ornament:)`), positioned outside the
  window's own content rather than floating inside it. `RichTextEditor.swift`'s `editor(_:_:)`
  branches on `#if os(visionOS)` to attach the toolbar via
  `.ornament(visibility: .automatic, attachmentAnchor: .scene(.bottom), contentAlignment: .center)`
  instead of `.safeAreaInset`, keeping the iOS/macOS behavior unchanged in the `#else` branch. This
  was a deliberate product decision, not a side effect of making the Liquid Glass swap compile —
  see `docs/visionos.md`'s "What this does *not* resolve" section for why it was left open rather
  than decided silently.

Both changes were verified by direct compilation against the real visionOS SDK, and
`examples/visionos-demo` builds and runs (unsigned, in the visionOS Simulator) on top of them —
see that example's own README for what it demonstrates. Not yet done: a hands-on typing/formatting
pass the way macOS got (see "The macOS editor" above), and any pass on real Vision Pro hardware.

## One document, one mutable copy

`RichTextEditorModel` (the `@Observable` state behind `RichTextEditor`) holds no `Delta` copy
that has to be kept in sync with the live text view. `UITextView.textStorage` is the document
while an editing session is active; the model reads and writes through it directly, and only
encodes back to a `Delta` (into the `Binding<Delta>` the host provided) on an idle debounce, on
`onDisappear`, and on a scene-phase change. Two independent mutable copies of the same document —
one the text view renders, one a `@State` var elsewhere — is exactly the shape of bug that made
`TextEditor`'s binding hazardous in the first place; this design removes the whole class rather
than being careful around it every time something touches the model.

## Images: real inline attachments, and the one bug that shape introduces

Images are real `NSTextAttachment`s embedded directly in the text storage — not segmented out
into a separate view interleaved with text editors, which was the fork point's original design
before this extraction (see `PROVENANCE.md`). This is simpler (one `UITextView`, not a stack of
them) but introduces a real, structural hazard that has to be guarded explicitly: an
`NSTextAttachment` with no `bounds` set falls back to the image's own pixel dimensions
*interpreted as points*, since an image decoded straight from JPEG bytes has `scale == 1` — a
~2000-pixel-wide photo would render ~2000 *points* wide, wildly overflowing any reading-width
column. `FittedImageTextAttachment` (`RichTextCore`) overrides `attachmentBounds` to fit the
text container's current line-fragment width, aspect ratio preserved, and both the decode path
and `RichTextEditorModel.insertImage` use it — never plain `NSTextAttachment`.

Two structural invariants images introduce, both enforced at the edit boundary
(`RichTextEditorModel.shouldChangeText`) rather than only at encode time:

- An image must be preceded and followed by a bare newline in the *Delta*, even though it's
  visually inline in the buffer — typing immediately adjacent to an attachment is redirected onto
  a fresh line rather than allowed to merge onto the image's line.
- Backspacing the newline immediately after an attachment deletes the whole image, matching what
  a user expects "delete this line" to do at an image boundary, rather than merging text onto the
  image's line.

`NSDeltaCodec.encode` also self-heals a missing terminator rather than ever producing an invalid
`Delta`, as a second layer behind the edit-time guard.

## Sync and conflicts: a contract, not a backend

`RichTextCore/Reconciliation.swift` is a pure, backend-agnostic three-way comparison (`base`,
`mine`, `theirs`) that decides `push` / `pull` / `inSync` / `conflict(...)`, never resolving a
real conflict automatically — that's a product decision every host makes for itself, not
something this library should decide silently. This is the client-side half of what any backend
adapter needs to support; see `docs/backends/README.md` for the actual storage contract
(a `Delta` column, a version/updated-at pair, and an object-key image reference resolved to a URL
only at read time) and per-database guidance for implementing it.
