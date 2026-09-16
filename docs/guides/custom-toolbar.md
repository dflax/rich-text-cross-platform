# Custom toolbar

The default toolbar (`RichTextFormatBar`) uses the Liquid Glass API and this package's iOS 26
minimum. Replace it entirely via `RichTextEditorConfiguration.toolbar` — useful for matching an
existing design system, or supporting an OS version below 26 for the rest of your app (the editor
itself still needs iOS 26 for its TextKit 2 behavior; only the toolbar *chrome* is swappable):

```swift
RichTextEditor(
    delta: $delta,
    imageStore: imageStore,
    configuration: RichTextEditorConfiguration(
        toolbar: { model in AnyView(MyToolbar(model: model)) }
    )
)
```

The closure receives the live `RichTextEditorModel` — the exact object the default toolbar
drives. Build your own controls against its public surface:

| What | How |
|---|---|
| Bold / italic / underline / strike | `model.toggleBold()`, `.toggleItalic()`, `.toggleUnderline()`, `.toggleStrike()` — and `.isBoldActive`, `.isItalicActive`, `.isUnderlineActive`, `.isStrikeActive` to reflect current state |
| Paragraph style (body / header 1&2 / bulleted / numbered) | `model.setLineStyle(_:)` with a `RichTextEditorModel.LineStyle` case, and `model.currentLineStyle` to reflect the active one. Applying the already-active style reverts to `.body` — mirror that toggle behavior rather than only ever setting forward |
| Links | `model.linkEditContext` tells you whether the cursor/selection is on an existing link (pre-fill your own UI from its `text`/`url`), a plain selection (turn it into a link), or neither (insert new linked text at the cursor). `model.applyLink(text:url:range:)` is the single write path for all three; `model.removeLink(range:)` strips a link's URL while keeping its text |
| Images | `model.insertImage(key:alt:image:)` once you have an uploaded key — `RichTextEditor` itself handles the picker/upload flow around its own image button; a fully custom toolbar that wants its own image-insert UI calls this directly after uploading |
| Errors | `model.reportError(_:)` surfaces through the same banner the default toolbar's flows use; `model.lastError`/`model.integrityFailure`/`model.isDirty` if you want your own presentation instead |

Every one of these already enforces the shared vocabulary (see `vocabulary-enforcement.md`) —
nothing about building your own toolbar UI weakens that.

See [`../../examples/rich-text-editor-demo/RichTextEditorDemo/CustomToolbarEditorView.swift`](../../examples/rich-text-editor-demo/RichTextEditorDemo/CustomToolbarEditorView.swift)
for a complete, minimal example.
