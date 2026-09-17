@testable import RichTextEditor
import Testing
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Regression coverage for a real bug caught by hands-on device testing: `ImageDownscaler` used
/// to decode via `UIImage(data:)`/`NSImage(data:)`, which failed outright on a HEIC photo picked
/// from the Photos library (iOS's own default camera format since iOS 11) - the picker's own
/// error surfaced as "Could not re-encode the picked image." Rewritten on `CGImageSource`/
/// `CGImageDestination` (ImageIO), which is genuinely cross-platform - no `#if canImport(UIKit)`
/// guard needed here, unlike `RichTextEditorModelTests.swift`.
@Suite("ImageDownscaler")
struct ImageDownscalerTests {
    /// A real, decodable image of the given format and pixel size - not a hand-rolled byte
    /// fixture, so this exercises the exact same ImageIO encode/decode round trip a real photo
    /// would.
    static func makeImageData(format: UTType, width: Int, height: Int) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!

        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, format.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cgImage, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    @Test("decodes and downscales a HEIC source - the real device bug this regression-tests")
    func downscalesHEIC() throws {
        let heicData = Self.makeImageData(format: .heic, width: 3000, height: 2000)

        let jpeg = try #require(ImageDownscaler.downscaledJPEG(from: heicData, configuration: .init(maxLongEdge: 800, jpegQuality: 0.75)))

        #expect(CGImageSourceCreateWithData(jpeg as CFData, nil) != nil, "output must itself be a decodable image")
        let size = try #require(Self.pixelSize(of: jpeg))
        #expect(size.width == 800)
        // ImageIO's own thumbnail-scaling rounds internally; within 1px of the naive aspect-ratio
        // calculation is what "aspect ratio preserved" means here, not exact pixel-for-pixel math.
        let expectedHeight = Int((2000.0 / 3000.0 * 800).rounded())
        #expect(abs(size.height - expectedHeight) <= 1)
    }

    @Test("decodes and downscales a JPEG source (no regression on the original supported format)")
    func downscalesJPEG() throws {
        let jpegData = Self.makeImageData(format: .jpeg, width: 3000, height: 2000)
        let jpeg = try #require(ImageDownscaler.downscaledJPEG(from: jpegData, configuration: .init(maxLongEdge: 800, jpegQuality: 0.75)))
        let size = try #require(Self.pixelSize(of: jpeg))
        #expect(size.width == 800)
    }

    @Test("decodes and downscales a PNG source (no regression on the original supported format)")
    func downscalesPNG() throws {
        let pngData = Self.makeImageData(format: .png, width: 3000, height: 2000)
        let jpeg = try #require(ImageDownscaler.downscaledJPEG(from: pngData, configuration: .init(maxLongEdge: 800, jpegQuality: 0.75)))
        let size = try #require(Self.pixelSize(of: jpeg))
        #expect(size.width == 800)
    }

    @Test("does not upscale an image already smaller than maxLongEdge")
    func doesNotUpscale() throws {
        let jpegData = Self.makeImageData(format: .jpeg, width: 400, height: 300)
        let jpeg = try #require(ImageDownscaler.downscaledJPEG(from: jpegData, configuration: .init(maxLongEdge: 1600, jpegQuality: 0.75)))
        let size = try #require(Self.pixelSize(of: jpeg))
        #expect(size.width == 400)
        #expect(size.height == 300)
    }

    @Test("returns nil for data that is not a decodable image")
    func returnsNilForGarbageData() {
        let garbage = Data("not an image".utf8)
        #expect(ImageDownscaler.downscaledJPEG(from: garbage, configuration: .default) == nil)
    }
}
