# RichTextEditorVisionDemo

A visionOS sample app showing `RichTextEditor` used the way visionOS itself is shaped: several
documents open at once, each in its own floating window you can place around you, rather than one
document at a time behind a navigation stack. This is a separate app from
[`examples/rich-text-editor-demo`](../rich-text-editor-demo) (the iOS/iPadOS/macOS sample) — not
a copy of it with a platform flag flipped.

## What's here

- **A gallery window** (`DocumentGalleryView`) listing a handful of sample documents. Tapping one
  opens it in its own window; the `+` button creates a new untitled document and opens that too.
- **A document window per open document** (`DocumentWindowView`), each hosting `RichTextEditor`
  on its own `Document`. Open two or three from the gallery and you'll have that many independent
  windows, each resizable and separately closable, editing the same shared in-memory document
  list (`DocumentLibrary`).
- **The default toolbar sits in an ornament**, not docked to the bottom of the text like it is on
  iOS/macOS. That's `RichTextEditor` itself doing this on visionOS (see
  `Sources/RichTextEditor/RichTextEditor.swift`), not something this app opts into — visionOS's
  own idiom for a persistent secondary control surface is an ornament attached to the window
  edge, not a floating bar inside scrollable content.

Documents and images are both in-memory for this demo (`DocumentLibrary`, `DemoServices`) — same
approach as the other example app. Nothing here talks to a real backend; see `docs/backends/` for
that.

## Running it in the visionOS Simulator

```
open RichTextEditorVisionDemo.xcodeproj
```

Pick an Apple Vision Pro Simulator destination and hit Run. On first launch you'll land in the
gallery window. Tap a document to open it in its own window — the two windows are independent, so
you can drag them apart, resize either one, or open a third document alongside them.

There's no real Vision Pro hardware pass on this yet — everything above has only been run in
Simulator. If you try it on a real device and hit something Simulator didn't catch (window
placement, ornament behavior, hand/eye input on the toolbar), that's expected territory to find
bugs in.

## Why two windows, not one

visionOS's genuinely distinct capability over iOS and macOS is that an app can have several
independent floating windows open around a person at the same time — there's no equivalent
"several documents visible at once, positioned in physical space" interaction on a phone, tablet,
or a single Mac display. A `WindowGroup(for: Document.ID.self)` is what makes this possible:
`DocumentGalleryView` calls `openWindow(id: "document", value: document.id)` for each document a
person picks, and the system creates (or brings forward) that document's own window rather than
pushing a new screen onto the gallery's own navigation stack.

Both `WindowGroup`s share one `DocumentLibrary` instance, injected via `.environment(_:)` from
`RichTextEditorVisionDemoApp`. A document window doesn't own a private copy of its `Delta` —
`DocumentLibrary.binding(for:)` looks the document up by id on every access and hands back a
`Binding<Delta>` that reads and writes straight into the shared list, so the gallery's preview
text and a document's own open window stay consistent without any extra syncing code.

**On window placement:** the document `WindowGroup` has a `.defaultWindowPlacement` that opens
each new document window `.trailing` the gallery window. Without that, visionOS picks a default
position for a newly opened window with no relationship to the window you opened it from — which
can land directly behind or fully overlapping the window you're already looking at, so tapping a
document can look like nothing happened. If that ever comes back (e.g. you remove the gallery
window's explicit `id: "gallery"`, which is what `.defaultWindowPlacement` looks up to find it),
try the Simulator's recenter control first before assuming the tap itself didn't register.

## Changing the project

If you add, remove, or rename a source file, or edit `project.yml`:

```
brew install xcodegen   # once
xcodegen generate       # from this directory, regenerates RichTextEditorVisionDemo.xcodeproj
```

## Running on a real Vision Pro

Select the `RichTextEditorVisionDemo` target, open Signing & Capabilities, and pick your own team
under "Team." A free personal-team Apple ID is enough for a device you own — no paid Apple
Developer Program membership required.

Don't set `CODE_SIGNING_ALLOWED` or `CODE_SIGNING_REQUIRED` to `false` in `project.yml` as a way
to build without picking a team — that forces a permanently unsigned binary no matter what team
you pick afterward. It'll build and run fine in Simulator, then fail to install on a real device
with "The executable is not codesigned." Signing here is left on `Automatic` with no team
hardcoded, which is what lets your own team selection actually take effect. CI (and the build
command below) passes `CODE_SIGNING_ALLOWED=NO` instead, since a headless build has no team to
pick.

```
xcodebuild build -project RichTextEditorVisionDemo.xcodeproj -scheme RichTextEditorVisionDemo \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' CODE_SIGNING_ALLOWED=NO
```
