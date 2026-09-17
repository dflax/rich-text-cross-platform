import Foundation
import ImageIO
import UniformTypeIdentifiers

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
///
/// Built on `CGImageSource`/`CGImageDestination` (ImageIO), not `UIImage(data:)`/`NSImage(data:)`
/// plus a manual redraw - real hands-on device testing found the previous UIKit-based path failed
/// outright on a HEIC photo picked from the Photos library (iOS's own default camera format since
/// iOS 11). ImageIO is Apple's own lower-level, format-agnostic decoder - the same one `UIImage`/
/// `NSImage` sit on top of - and its thumbnail-generation entry point does the decode, EXIF-
/// orientation correction, and downscale in one pass, which is both more robust across formats
/// (HEIC/HEIF included) and removes the `#if os(macOS)` split this function used to need entirely.
enum ImageDownscaler {
    static func downscaledJPEG(from data: Data, configuration: ImageDownscaling) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: configuration.maxLongEdge,
            // Bakes EXIF orientation into the pixel data - without this, a portrait HEIC photo
            // (whose raw pixel buffer is often landscape, corrected only by an orientation tag)
            // would re-encode sideways.
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let destinationOptions: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: configuration.jpegQuality]
        CGImageDestinationAddImage(destination, cgImage, destinationOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return output as Data
    }
}
