import RichTextCore
import RichTextEditor
import SwiftUI

/// A demo `RichTextImageUploading` that "uploads" by copying the image into the shared
/// `ImageStore`'s own cache directory under a fresh key and returning that key immediately —
/// standing in for a real network upload (S3, B2, Firebase Storage, …) so this screen runs with
/// no backend at all. A real conformance's `upload(_:)` sends `imageData` to your actual object
/// store and returns the key it was stored under; see docs/guides/getting-started-ios.md and
/// docs/backends/ for real examples.
struct DemoImageUploader: RichTextImageUploading {
    let cacheDirectory: URL

    func upload(_ imageData: Data) async throws -> String {
        let key = "demo-images/\(UUID().uuidString).jpg"
        let destination = cacheDirectory.appending(path: key)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try imageData.write(to: destination)
        return key
    }
}

struct ImageUploadEditorView: View {
    @State private var delta = Delta(ops: [.text("Add a photo with the toolbar's image button.\n")])

    var body: some View {
        RichTextEditor(
            delta: $delta,
            imageStore: DemoServices.imageStore,
            imageUploader: DemoImageUploader(cacheDirectory: DemoServices.imageStore.directory)
        )
        .navigationTitle("With Images")
        .navigationBarTitleDisplayMode(.inline)
    }
}
