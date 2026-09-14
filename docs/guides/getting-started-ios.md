# Getting started — iOS/iPadOS

## Add the packages

`RichTextCore` and `RichTextEditor` are two separate Swift packages (`swift/RichTextCore/`,
`swift/RichTextEditor/`) — see `docs/ROADMAP.md`'s Open Decisions for why, and for the current
distribution story (local path only for now, not yet a single remote `.package(url:)` add):

```swift
// Package.swift
dependencies: [
    .package(path: "../rich-text-cross-platform/swift/RichTextCore"),
    .package(path: "../rich-text-cross-platform/swift/RichTextEditor"),
],
targets: [
    .target(name: "YourApp", dependencies: ["RichTextCore", "RichTextEditor"])
]
```

Or in Xcode: File → Add Package Dependencies… → Add Local…, once for each of
`swift/RichTextCore/` and `swift/RichTextEditor/`.

**Minimum deployment target: iOS 26 / iPadOS 26** — see `docs/ROADMAP.md`'s Open Decisions for
why, and the plan to lower it.

## The three things you provide

`RichTextEditor` needs a `Delta` to edit, an `ImageStore` to resolve/cache images through, and
(only if you want image insertion to work) something that uploads image bytes somewhere.

### 1. A `Delta`

This is your document. Load it from wherever you persist documents (see `docs/backends/`) and
bind to it:

```swift
@State private var delta: Delta = /* decoded from your backend, or Delta(ops: [.text("\n")]) for a new document */

var body: some View {
    RichTextEditor(delta: $delta, imageStore: imageStore)
}
```

`RichTextEditor` writes back into this binding as the user edits (debounced, and on disappear/
backgrounding) — observe it with `.onChange(of: delta)` if you need to know when to persist.

### 2. An `ImageStore`

Caches images to disk so a document that rendered once still renders offline. Point it at a real
directory and a real `ImageFetching` conformance:

```swift
let imageStore = try ImageStore(
    fetcher: PublicURLImageFetcher(baseURL: URL(string: "https://your-bucket.example.com")!)
)
```

`ImageStore.defaultDirectory()` (used when you omit `directory:`) lives in Application Support,
namespaced by your app — pass `namespace:` if you're running more than one `ImageStore` in the
same app. `PublicURLImageFetcher` covers "plain HTTPS GET from a public bucket/CDN"; write your
own `ImageFetching` conformance if reads need real authorization.

### 3. A `RichTextImageUploading` (optional)

Only needed if you want the toolbar's image button to do anything:

```swift
struct MyUploader: RichTextImageUploading {
    func upload(_ imageData: Data) async throws -> String {
        // Send imageData to your object store; return the key it was stored under —
        // never a URL. See docs/backends/README.md's "Images" row for why.
        let key = "doc-images/\(UUID().uuidString).jpg"
        try await myBucket.put(key: key, data: imageData)
        return key
    }
}

RichTextEditor(delta: $delta, imageStore: imageStore, imageUploader: MyUploader())
```

Without an `imageUploader`, the toolbar's photo button still shows (unless you turn it off — see
below) but reports an error rather than silently doing nothing.

## Configuration

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

See [`custom-toolbar.md`](custom-toolbar.md) for replacing the toolbar entirely, and
[`../../examples/ios-basic/`](../../examples/ios-basic/) for all three shown side by side.

## Saving reliably

See [`saving.md`](saving.md) — the short version: provide `onDone` and call it from your own
dismissal action rather than tearing this view down some other way, or read that doc's race
description before relying on `onDisappear` alone.

## Vocabulary enforcement

You don't configure this — see [`vocabulary-enforcement.md`](vocabulary-enforcement.md) for what
it does and why it's not optional.
