import SwiftUI

@main
struct RichTextEditorVisionDemoApp: App {
    @State private var library = DocumentLibrary()

    var body: some Scene {
        WindowGroup(id: "gallery") {
            DocumentGalleryView()
                .environment(library)
        }
        .defaultSize(width: 420, height: 600)

        // A second, independent window kind — one instance per document id, each opened
        // explicitly via `openWindow(id: "document", value:)` from the gallery. This is the
        // multi-window story this demo exists to show: several of these can be open at once,
        // each a separate floating window a person can place around them, unlike the single
        // navigation stack the iOS/macOS example app uses for the same editor.
        WindowGroup(id: "document", for: Document.ID.self) { $documentID in
            if let documentID {
                DocumentWindowView(documentID: documentID)
                    .environment(library)
            } else {
                ContentUnavailableView("No Document", systemImage: "doc.text")
            }
        }
        .defaultSize(width: 720, height: 900)
        // Without this, a newly opened document window has no relationship to the gallery
        // window it was opened from — the system picks a default position that can land
        // directly behind or fully overlapping the window you're already looking at, which
        // reads as "nothing happened" when you tap a document. Placing it beside the gallery
        // window (when the gallery is actually open) makes every new document window land
        // somewhere you'll actually see it.
        .defaultWindowPlacement { _, context in
            if let gallery = context.windows.first(where: { $0.id == "gallery" }) {
                WindowPlacement(.trailing(gallery))
            } else {
                WindowPlacement()
            }
        }
    }
}
