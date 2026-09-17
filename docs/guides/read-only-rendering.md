# Read-only rendering with `ReadLayout`

`ReadLayout.groups(from:)` (in `RichTextCore`) turns a `Delta` into a small number of renderable
groups — text spans, images, and merge-field chips — designed for real, continuous, native
drag-to-select across paragraph and heading boundaries. See its own doc comment for why that rules
out a `VStack` of one view per block.

## `Text(AttributedString)` does not render every attribute this produces

Headers, inline emphasis, and list markers are all baked into the `AttributedString` a `.text`
group carries — that part renders correctly through a plain SwiftUI `Text`. A list line's
**hanging indent** (`.paragraphStyle`, `headIndent`/`firstLineHeadIndent`, matching the edit path's
own `NSDeltaCodec.applyVisualBlockStyling` exactly) does not: SwiftUI's `Text` silently ignores
`.paragraphStyle` entirely, confirmed by direct measurement — an `NSHostingView` wrapping an
indented vs. non-indented `Text` at the same fixed width produces byte-identical fitting heights.
The attribute is genuinely present in the `AttributedString` (it round-trips correctly through
`NSAttributedString` bridging); `Text` just never applies it during layout.

**Symptom if you render `.text` groups via plain `Text`:** a wrapped bullet or numbered list item's
continuation line falls flush under the marker instead of aligning with the first line's text —
visually wrong, but easy to miss in a quick look since a short list item that never wraps looks
identical either way.

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
