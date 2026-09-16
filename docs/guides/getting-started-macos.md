# Getting started — macOS

`RichTextEditor` on macOS is the same public API as iOS/iPadOS — `RichTextEditor`,
`RichTextEditorModel`, `RichTextTextView`, `RichTextEditorConfiguration`,
`RichTextImageUploading`, `ImageDownscaling` — backed by a real `NSTextView` on TextKit 2 instead
of `UITextView`. If you've already read
[`getting-started-ios.md`](getting-started-ios.md), most of it applies unchanged; this page covers
what's actually different on macOS.

## Add the package

Same as iOS — one `Package.swift`, two products:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/dflax/rich-text-cross-platform", from: "0.3.0")
],
targets: [
    .target(name: "YourApp", dependencies: ["RichTextCore", "RichTextEditor"])
]
```

Or in Xcode: File → Add Package Dependencies…, paste the repo URL, pick "Up to Next Minor
Version" starting at `0.3.0`, and link both `RichTextCore` and `RichTextEditor`.

**Minimum deployment target: macOS 26** — see `docs/ROADMAP.md`'s Decided section for why this
isn't being lowered.

## The three things you provide

Identical to iOS: a `Delta` to edit, an `ImageStore`, and (optionally) a `RichTextImageUploading`.
See [`getting-started-ios.md`](getting-started-ios.md#the-three-things-you-provide) for the full
walkthrough — none of it is iOS-specific.

```swift
@State private var delta: Delta = /* decoded from your backend, or Delta(ops: [.text("\n")]) for a new document */

var body: some Scene {
    WindowGroup {
        RichTextEditor(delta: $delta, imageStore: imageStore, imageUploader: uploader)
    }
}
```

## What's actually different from iOS

- **The text view.** Under the hood this is a real `NSTextView(usingTextLayoutManager: true)`,
  not `UITextView` — but that's an implementation detail behind `RichTextTextView`; you don't
  interact with `NSTextView` directly. If you're curious what changed to make this work (TextKit 2
  opt-in, selection as a single collapsed range, `NSTextViewDelegate`'s different method shapes),
  see `docs/ARCHITECTURE.md`'s macOS section — none of it affects the public API.
- **No navigation chrome assumptions.** The iOS guide's examples sit inside whatever navigation
  stack your app already has; on macOS, `RichTextEditor` just as happily fills a plain
  `WindowGroup` scene, a pane in a `NavigationSplitView`, or a sheet. Nothing about it assumes a
  `UINavigationController`-style container either way.
- **Image insertion still goes through `PhotosPicker`.** SwiftUI's `PhotosPicker` has worked on
  macOS since macOS 13, so the toolbar's photo button and the upload flow in
  `RichTextImageUploading` are identical code on both platforms — no macOS-specific image-picking
  API to learn.
- **App Sandbox, if you use it.** The bundled example app (`examples/rich-text-editor-demo/`)
  doesn't enable App Sandbox, so it hasn't needed to work out which entitlements
  `ImageStore.defaultDirectory()` (a directory under Application Support) or `PhotosPicker` need
  under sandboxing. If your app *does* sandbox, budget time to check Apple's current entitlement
  requirements for both — this hasn't been verified against a sandboxed target from this project.
- **Keyboard shortcuts and menu commands are yours to add.** The toolbar handles mouse/trackpad
  and touch-bar-free interaction, but standard Mac conventions — ⌘B for bold, a Format menu, etc.
  — aren't wired up automatically. `RichTextEditorModel`'s actions (`toggleBold`, `setLineStyle`,
  …) are the same ones the toolbar calls, so wiring a `.keyboardShortcut`-annotated `Button` or a
  `CommandMenu` to them is straightforward; see
  [`custom-toolbar.md`](custom-toolbar.md) for how to reach the model from outside the default
  toolbar.

## Configuration

Identical to iOS:

```swift
RichTextEditor(
    delta: $delta,
    imageStore: imageStore,
    imageUploader: uploader,
    configuration: RichTextEditorConfiguration(
        allowsImages: true,
        allowsLinks: true,
        imageDownscaling: .default   // 1600pt long edge, 0.75 JPEG quality
    )
)
```

See [`../../examples/rich-text-editor-demo/`](../../examples/rich-text-editor-demo/) — all three
configuration variants run on "My Mac" from the same project as iOS/iPadOS, no separate target.

## Saving reliably

See [`saving.md`](saving.md). The `onDone`/`onDisappear` guidance there applies as written — macOS
has its own equivalents of backgrounding to worry about (a window closing, the app quitting) and
the same debounce race applies if you tear the view down without giving it a chance to save.

## Vocabulary enforcement

Not configurable, and not platform-specific — see
[`vocabulary-enforcement.md`](vocabulary-enforcement.md).
