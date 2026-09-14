import RichTextCore
import RichTextEditor
import SwiftUI

/// The simplest possible integration: a `Delta` binding and an `ImageStore` — no image
/// upload wired up, so the "insert photo" button never appears
/// (`RichTextEditorConfiguration.allowsImages` defaults to `true`, but there is nothing to
/// upload to without an `imageUploader`, so omitting it is enough for a text-only editor;
/// the toolbar hides the photo button once `allowsImages` is turned off explicitly here to
/// make the "text only" intent visible in the config rather than implicit).
struct MinimalEditorView: View {
    @State private var delta = Delta(ops: [.text("Type something…\n")])

    var body: some View {
        RichTextEditor(
            delta: $delta,
            imageStore: DemoServices.imageStore,
            configuration: RichTextEditorConfiguration(allowsImages: false)
        )
        .navigationTitle("Minimal")
        .navigationBarTitleDisplayMode(.inline)
    }
}
