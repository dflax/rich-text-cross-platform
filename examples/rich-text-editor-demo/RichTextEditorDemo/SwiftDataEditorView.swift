import RichTextCore
import RichTextEditor
import SwiftData
import SwiftUI

/// A document persisted through SwiftData rather than held in memory like the other three demo
/// screens — this is what wiring `RichTextEditor` up to a real, on-device store looks like end to
/// end: create, list, edit, delete, all surviving a relaunch.
///
/// Every stored property has a default value at declaration, not just in `init` — that's not
/// incidental. It's what lets this same model be synced via CloudKit later (see
/// `RichTextEditorDemoApp.swift`) without changing the model itself: CloudKit-backed SwiftData
/// requires every attribute to be optional or have a default.
@Model
final class StoredDocument {
    var title: String = "Untitled"
    var deltaJSON: Data = Delta.empty.canonicalJSON()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(title: String = "Untitled", deltaJSON: Data = Delta.empty.canonicalJSON()) {
        self.title = title
        self.deltaJSON = deltaJSON
        self.createdAt = .now
        self.updatedAt = .now
    }
}

struct SwiftDataEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredDocument.updatedAt, order: .reverse) private var documents: [StoredDocument]
    @State private var editingDocument: StoredDocument?

    var body: some View {
        List {
            ForEach(documents) { document in
                Button { editingDocument = document } label: {
                    row(for: document)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: delete)
        }
        .overlay {
            if documents.isEmpty {
                ContentUnavailableView(
                    "No documents yet",
                    systemImage: "doc.text",
                    description: Text("Tap + to create one — it's written to SwiftData immediately, not just held in memory.")
                )
            }
        }
        .navigationTitle("SwiftData")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Document", systemImage: "square.and.pencil", action: addDocument)
            }
        }
        .sheet(item: $editingDocument) { document in
            NavigationStack {
                SwiftDataDocumentEditorView(document: document)
            }
        }
    }

    private func row(for document: StoredDocument) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(document.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(document.updatedAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func addDocument() {
        let document = StoredDocument()
        modelContext.insert(document)
        editingDocument = document
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { modelContext.delete(documents[index]) }
    }
}

private struct SwiftDataDocumentEditorView: View {
    @Bindable var document: StoredDocument
    @Environment(\.dismiss) private var dismiss
    @State private var delta: Delta

    init(document: StoredDocument) {
        self.document = document
        // Decode once, up front — RichTextEditor owns this Delta from here on and writes back
        // into the binding itself; see docs/guides/saving.md for exactly when.
        _delta = State(initialValue: (try? Delta.decode(json: document.deltaJSON)) ?? .empty)
    }

    var body: some View {
        RichTextEditor(delta: $delta, imageStore: DemoServices.imageStore, onDone: { dismiss() })
            .navigationTitle(document.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onChange(of: delta) { _, newValue in
                document.deltaJSON = newValue.canonicalJSON()
                document.updatedAt = .now
                let firstLine = newValue.plainText.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
                document.title = firstLine.isEmpty ? "Untitled" : String(firstLine.prefix(60))
            }
    }
}
