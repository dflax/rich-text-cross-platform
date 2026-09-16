import Foundation
import RichTextCore
import RichTextEditor

/// A throwaway, in-memory `ImageStore` shared by every document window — real apps point this at
/// a real cache directory (`ImageStore.defaultDirectory()`) and a real `ImageFetching`
/// conformance; see docs/guides/getting-started-ios.md. Mirrors the pattern
/// `examples/rich-text-editor-demo` already uses for the same reason.
enum DemoServices {
    static let imageStore: ImageStore = {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: "RichTextEditorVisionDemo-\(UUID().uuidString)")
        return try! ImageStore(directory: directory, fetcher: LocalDirectoryImageFetcher(directory: directory))
    }()
}

/// "Uploads" an image by copying it into the shared `ImageStore`'s own cache directory under a
/// fresh key — standing in for a real network upload so this demo runs with no backend at all.
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
