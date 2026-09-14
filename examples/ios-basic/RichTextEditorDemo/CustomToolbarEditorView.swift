import RichTextCore
import RichTextEditor
import SwiftUI

/// Replaces the default Liquid Glass toolbar entirely via `RichTextEditorConfiguration.toolbar`
/// — useful for matching an existing design system, or for supporting an OS version below this
/// package's iOS 26 minimum for the rest of your app (the editor itself still needs iOS 26 for
/// its TextKit 2 behavior; only the *toolbar chrome* is swappable here). The closure receives the
/// live `RichTextEditorModel` — the same object the default toolbar drives — so a custom toolbar
/// has access to exactly the same actions (`setLineStyle`, `toggleBold`, `currentLineStyle`, …).
struct CustomToolbarEditorView: View {
    @State private var delta = Delta(ops: [.text("This editor has a plain, minimal toolbar instead of the default one.\n")])

    var body: some View {
        RichTextEditor(
            delta: $delta,
            imageStore: DemoServices.imageStore,
            configuration: RichTextEditorConfiguration(
                allowsImages: false,
                toolbar: { model in AnyView(SimpleToolbar(model: model)) }
            )
        )
        .navigationTitle("Custom Toolbar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SimpleToolbar: View {
    let model: RichTextEditorModel

    var body: some View {
        HStack(spacing: 20) {
            Button("B") { model.toggleBold() }
                .fontWeight(model.isBoldActive ? .heavy : .regular)
            Button("I") { model.toggleItalic() }
                .italic()
            Button("•") { model.setLineStyle(model.currentLineStyle == .bullet ? .body : .bullet) }
                .fontWeight(model.currentLineStyle == .bullet ? .heavy : .regular)
            Button("1.") { model.setLineStyle(model.currentLineStyle == .ordered ? .body : .ordered) }
                .fontWeight(model.currentLineStyle == .ordered ? .heavy : .regular)
        }
        .font(.title3)
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
