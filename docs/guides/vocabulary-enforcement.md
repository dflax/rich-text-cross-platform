# Vocabulary enforcement

`RichTextEditor` never lets an attribute outside the shared vocabulary (bold, italic, underline,
strike, link, header 1/2, bulleted/ordered list, image+alt) reach the document — not
configurable, because a document that accumulated stray attributes from one client would render
differently, or fail to round-trip, on another. Three layers, in order of how content actually
reaches the buffer:

## 1. The system's own format UI is closed off

`allowsEditingTextAttributes = false` on the underlying `UITextView` means the system's own
selection-menu font/color controls never appear — every attribute the editor ever writes comes
from its own toolbar (or a custom one you supply — see `custom-toolbar.md`), which only ever
calls vocabulary-producing methods (`toggleBold()`, `setLineStyle(_:)`, …).

## 2. Paste is sanitized at the point of insertion

A paste from another app is the realistic remaining vector — Notes or Safari copy rich text
carrying arbitrary fonts, colors, point sizes, and foreign paragraph styles/lists.
`RichTextCore.NSDeltaCodec.sanitizedForPaste(_:)` strips all of that down to exactly the
vocabulary before it's inserted, discarding rather than translating (a pasted `<h1>` does not
become this editor's Header 1 — the bar is "blocked," not "reinterpreted"; guessing at a
translation risks fabricating structure the user never actually chose from the toolbar). Pasted
images are dropped entirely — this editor's images only ever arrive through
`RichTextImageUploading`, the only path that produces a valid, resolvable key.

## 3. A defensive backstop catches anything that slips past #2

`RichTextCore.VocabularyTextStorageDelegate`, attached to the text view's `NSTextStorage`,
clamps every attribute on every edit — a programmatic mutation, a future code path that doesn't
go through paste interception — back to the vocabulary. It includes a re-entrancy guard (clamping
mutates the storage itself) and always re-derives header/list *visual* styling from the
underlying block token afterward, never leaving a stale paragraph style behind.

## What this means for you

Nothing to configure — this is always on. If you're building a custom toolbar (`custom-toolbar.md`),
only call the vocabulary-producing methods on `RichTextEditorModel` (`toggleBold`, `toggleItalic`,
`toggleUnderline`, `toggleStrike`, `setLineStyle(_:)`, `applyLink(text:url:range:)`,
`insertImage(key:alt:image:)`) — anything else you might be tempted to reach for directly on the
text view's storage bypasses these guarantees.
