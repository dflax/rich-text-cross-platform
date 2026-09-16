import Observation
import RichTextCore
import SwiftUI

/// The in-memory document list every window in this app shares — one instance, injected into
/// both `WindowGroup`s via `.environment(_:)`, so a document opened in its own floating window
/// (see `DocumentWindowView`) edits the same storage the gallery window lists. A real app would
/// back this with a real store (see docs/backends/); this demo only needs enough persistence to
/// make multiple simultaneous windows worth showing.
@MainActor
@Observable
final class DocumentLibrary {
    private(set) var documents: [Document]

    init(documents: [Document] = Document.samples) {
        self.documents = documents
    }

    @discardableResult
    func addDocument() -> Document.ID {
        let document = Document(title: "Untitled", delta: .empty)
        documents.append(document)
        return document.id
    }

    func title(for id: Document.ID) -> String {
        documents.first(where: { $0.id == id })?.title ?? "Untitled"
    }

    func rename(_ id: Document.ID, to title: String) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].title = title
    }

    /// A `Binding<Delta>` for one document, looked up by id on every access rather than a
    /// captured array index — the index would go stale the moment a document is added or
    /// removed while another document's window is already open.
    func binding(for id: Document.ID) -> Binding<Delta> {
        Binding(
            get: { [weak self] in
                self?.documents.first(where: { $0.id == id })?.delta ?? .empty
            },
            set: { [weak self] newValue in
                guard let self, let index = self.documents.firstIndex(where: { $0.id == id }) else { return }
                self.documents[index].delta = newValue
            }
        )
    }
}
