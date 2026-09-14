import RichTextCore
import RichTextEditor
import SwiftUI

/// Three ways to configure `RichTextEditor`, side by side, so the differences are obvious
/// rather than buried in separate app targets. Each demo owns its own `Delta` — in a real app
/// that would come from wherever you persist documents (see docs/backends/).
struct ConfigurationPickerView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("Minimal — text only", value: Demo.minimal)
                    NavigationLink("With image upload", value: Demo.withImages)
                    NavigationLink("Custom toolbar", value: Demo.customToolbar)
                } footer: {
                    Text("Each screen edits its own in-memory document — nothing here talks to a real backend. See docs/guides/getting-started-ios.md for wiring a real ImageStore/RichTextImageUploading.")
                }
            }
            .navigationTitle("RichTextEditor Demo")
            .navigationDestination(for: Demo.self) { demo in
                switch demo {
                case .minimal: MinimalEditorView()
                case .withImages: ImageUploadEditorView()
                case .customToolbar: CustomToolbarEditorView()
                }
            }
        }
    }

    private enum Demo: Hashable {
        case minimal, withImages, customToolbar
    }
}

/// A throwaway, in-memory `ImageStore` every demo screen shares — real apps point this at a
/// real cache directory (`ImageStore.defaultDirectory()`) and a real `ImageFetching`
/// conformance; see docs/guides/getting-started-ios.md.
enum DemoServices {
    static let imageStore: ImageStore = {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: "RichTextEditorDemo-\(UUID().uuidString)")
        return try! ImageStore(directory: directory, fetcher: LocalDirectoryImageFetcher(directory: directory))
    }()
}
