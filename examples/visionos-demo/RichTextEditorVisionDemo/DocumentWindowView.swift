import RichTextCore
import RichTextEditor
import SwiftUI

/// One document, in its own floating window. `RichTextEditorVisionDemoApp` opens one of these
/// per document via `openWindow(id: "document", value: document.id)`, so a person can have
/// several open around them at once, each independently movable, resizable, and closable —
/// there's nothing here coordinating between windows beyond the shared `DocumentLibrary` each
/// one edits into.
///
/// The default toolbar (`RichTextEditorConfiguration.toolbar` left `nil`) places itself in a
/// bottom `.ornament` on visionOS instead of docking to the content the way it does on iOS/macOS
/// — see `RichTextEditor.swift`'s `editor(_:_:)` and `docs/ARCHITECTURE.md`'s visionOS section.
/// Leaving generous space below the text (rather than pinning the editor to the window's full
/// height) gives that ornament room to sit below the window without overlapping the content or
/// colliding with the window's own resize/close chrome.
struct DocumentWindowView: View {
    let documentID: Document.ID
    @Environment(DocumentLibrary.self) private var library

    var body: some View {
        RichTextEditor(
            delta: library.binding(for: documentID),
            imageStore: DemoServices.imageStore,
            imageUploader: DemoImageUploader(cacheDirectory: DemoServices.imageStore.directory)
        )
        .navigationTitle(library.title(for: documentID))
    }
}
