import SwiftUI

/// The app's one persistent window: a list of documents, each opened into its own resizable
/// floating window via `openWindow(id:value:)` rather than pushed onto a navigation stack in
/// this same window. That's the actual point of this demo — visionOS lets someone keep several
/// documents open side by side in physical space, which a single-window iOS/macOS app has no
/// real equivalent for.
struct DocumentGalleryView: View {
    @Environment(DocumentLibrary.self) private var library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationStack {
            List(library.documents) { document in
                Button {
                    openWindow(id: "document", value: document.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title)
                            .font(.headline)
                        Text(document.delta.plainText.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let id = library.addDocument()
                        openWindow(id: "document", value: id)
                    } label: {
                        Label("New Document", systemImage: "plus")
                    }
                }
            }
        }
        .frame(minWidth: 380, idealWidth: 420, minHeight: 480, idealHeight: 600)
    }
}
