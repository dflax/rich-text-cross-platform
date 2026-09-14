import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Long-edge pixel cap and JPEG quality for a picked image before it reaches
/// `RichTextImageUploading`. Applied once, at pick time — never re-derived from whatever the
/// image happens to already be, since a photo library asset can be arbitrarily large.
///
/// Deliberately outside `RichTextEditor.swift`'s `#if canImport(UIKit)` guard: this is a plain,
/// genuinely cross-platform value type (this file's own `ImageDownscaler` already compiles on
/// both UIKit and AppKit), and `RichTextEditorConfiguration` referencing it must not force it to
/// exist only on UIKit platforms.
public struct ImageDownscaling: Sendable {
    public var maxLongEdge: CGFloat
    public var jpegQuality: CGFloat

    public init(maxLongEdge: CGFloat, jpegQuality: CGFloat) {
        self.maxLongEdge = maxLongEdge
        self.jpegQuality = jpegQuality
    }

    /// 1600pt / 0.75 — sharp at typical reading-column widths on a Retina display, while
    /// keeping a multi-megabyte phone photo down to a few hundred KB.
    public static let `default` = ImageDownscaling(maxLongEdge: 1600, jpegQuality: 0.75)
}

/// Downscales and re-encodes a picked image before it reaches `RichTextImageUploading`.
///
/// Worth being precise about why this matters: a modern phone photo is several megabytes, and
/// every reader who opens the document pays that download. Shrinking once at upload time is the
/// only place the cost can be paid once instead of on every read.
enum ImageDownscaler {
    static func downscaledJPEG(from data: Data, configuration: ImageDownscaling) -> Data? {
        #if os(macOS)
        guard let source = NSImage(data: data) else { return nil }
        let size = source.size
        #else
        guard let source = UIImage(data: data) else { return nil }
        let size = source.size
        #endif
        guard size.width > 0, size.height > 0 else { return nil }

        let longEdge = max(size.width, size.height)
        let scale = longEdge > configuration.maxLongEdge ? configuration.maxLongEdge / longEdge : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        #if os(macOS)
        let resized = NSImage(size: target)
        resized.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: target))
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: configuration.jpegQuality])
        #else
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: configuration.jpegQuality)
        #endif
    }
}
