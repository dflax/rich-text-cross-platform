# Read-only rendering with `ReadLayout`

`ReadLayout.groups(from:)` (in `RichTextCore`) turns a `Delta` into a small number of renderable
groups — text spans, images, and merge-field chips — designed for real, continuous, native
drag-to-select across paragraph and heading boundaries. See its own doc comment for why that rules
out a `VStack` of one view per block.

## `Text(AttributedString)` does not render every attribute this produces

Headers, inline emphasis, and list markers are all baked into the `AttributedString` a `.text`
group carries — that part renders correctly through a plain SwiftUI `Text`, which resolves `Font`,
`inlinePresentationIntent`, `.underlineStyle`, and `.strikethroughStyle` through its own internal
SwiftUI-native pipeline. A list line's **hanging indent** (`.paragraphStyle`,
`headIndent`/`firstLineHeadIndent`, matching the edit path's own `NSDeltaCodec.
applyVisualBlockStyling` exactly) does not: SwiftUI's `Text` silently ignores `.paragraphStyle`
entirely, confirmed by direct measurement — an `NSHostingView` wrapping an indented vs.
non-indented `Text` at the same fixed width produces byte-identical fitting heights. The attribute
is genuinely present in the `AttributedString` (it round-trips correctly through `NSAttributedString`
bridging); `Text` just never applies it during layout.

**Symptom if you render `.text` groups via plain `Text`:** a wrapped bullet or numbered list item's
continuation line falls flush under the marker instead of aligning with the first line's text —
visually wrong, but easy to miss in a quick look since a short list item that never wraps looks
identical either way.

## The reverse problem: a real `UITextView`/`NSTextView` needs MORE than `Text` does

The fix below (render through a real TextKit-backed view) is not free — it trades `.paragraphStyle`
support for a different gap. `Text` resolves SwiftUI-scoped attributes (`Font`,
`inlinePresentationIntent`, `.underlineStyle`, `.strikethroughStyle`) through its own native
pipeline, never via `NSAttributedString` bridging. A real `UITextView`/`NSTextView` has no such
pipeline — it only reads standard `NSAttributedString.Key` values. Direct measurement (bridging an
`AttributedString` carrying these attributes through `NSAttributedString(_:)` and inspecting the
result) shows **none of them survive**: `Font` (concrete or semantic — this is not the
semantic-vs-concrete distinction it first appears to be), `inlinePresentationIntent`, and both
underline/strikethrough attributes all land under raw, uninterpreted custom keys carrying the
original SwiftUI-typed value, never a real `UIFont`/`NSFont`, font trait, or
`NSAttributedString.Key.underlineStyle`/`.strikethroughStyle` value.

**`ReadLayout.groups(from:)` fixes this by setting both scopes.** Alongside the SwiftUI-scoped
attributes (kept, so `Text`-based consumers are unaffected), it sets the equivalent
platform-scoped attribute — `AttributeScopes.UIKitAttributes`/`AppKitAttributes`'s own
`FontAttribute`, `UnderlineStyleAttribute`, and `StrikethroughStyleAttribute` — confirmed by direct
measurement to produce real, retrievable values under the standard `NSAttributedString.Key`s. Bold
and italic are merged into a real per-run `PlatformFont` (via `UIFontDescriptor`/`NSFontDescriptor`
symbolic traits) rather than left as `inlinePresentationIntent`, since that attribute alone doesn't
convert into real font traits either. If you consume `ReadLayout.groups(from:)`'s output through
your own renderer instead of the `ReadOnlyRichText` below, you get this fix for free; if you build
an `AttributedString` some other way for a real text view, remember that setting only the
SwiftUI-scoped attribute is not enough.

## Fix: render through a real text view, not `Text`

Host each `.text` group in a read-only `UITextView` (`isEditable = false`, `isSelectable = true`)
on iOS, or `NSTextView` (same flags) on macOS, instead of SwiftUI's `Text`. A real TextKit-backed
view honors `.paragraphStyle` correctly, and its own native selection is continuous across the
whole view's content — actually a better fit for the continuous-selection goal than
`.textSelection(.enabled)` on `Text`, not just a workaround for this one attribute.

```swift
struct ReadOnlyRichText: UIViewRepresentable {
    let attributedString: AttributedString

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.attributedText = NSAttributedString(attributedString)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = NSAttributedString(attributedString)
    }
}
```

Give it an intrinsic-content-size override (`sizeThatFits`, invalidated on `layoutSubviews`) so it
grows to fit inside a SwiftUI `VStack` without a separate height binding — the same trick
`RichTextEditorUITextView` uses for the editable side. `NSTextView`'s macOS equivalent is
`usageBoundsForTextContainer` on `NSTextLayoutManager`, invalidated on `layout()`.
