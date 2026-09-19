import Foundation

#if canImport(UIKit)
import UIKit
public typealias PlatformFont = UIFont
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
extension PlatformColor { static var richTextLabel: PlatformColor { .label } }
public typealias PlatformTextStorageEditActions = NSTextStorage.EditActions
#elseif canImport(AppKit)
import AppKit
public typealias PlatformFont = NSFont
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor
extension PlatformColor { static var richTextLabel: PlatformColor { .labelColor } }
public typealias PlatformTextStorageEditActions = NSTextStorageEditActions
#endif

// MARK: - Custom attribute keys

extension NSAttributedString.Key {
    /// The block attributes of the line a newline terminates, carried verbatim as the
    /// `NSAttributedString` counterpart of `BlockToken` (`Delta.swift`). Same contract: the
    /// encoder reads this back rather than ever inferring `header`/`list` from a rendered font
    /// size or paragraph style — see `docs/ARCHITECTURE.md`.
    public static let richTextBlockToken = NSAttributedString.Key("com.richtextcrossplatform.nsBlockToken")

    /// Carries the object key (and alt text) an image attachment was decoded from, tagged on
    /// the same single-character range as the `.attachment` key. `NSTextAttachment` has no
    /// slot for "the key this came from" — this is that slot. `encode` reads it back directly;
    /// it never infers a key from the loaded image.
    public static let richTextImageInfo = NSAttributedString.Key("com.richtextcrossplatform.nsImageInfo")

    /// Carries the field name a `mergeField` attachment was decoded from, tagged on the same
    /// single-character range as the `.attachment` key — the merge-field counterpart of
    /// `.richTextImageInfo`. `encode` reads it back directly; it never infers a name from the
    /// rendered pill.
    public static let richTextMergeFieldInfo = NSAttributedString.Key("com.richtextcrossplatform.nsMergeFieldInfo")
}

/// The payload of `.richTextImageInfo`.
public struct RichImageAttachmentInfo: Hashable, Sendable {
    public var key: String
    public var alt: String?

    public init(key: String, alt: String?) {
        self.key = key
        self.alt = alt
    }
}

/// The payload of `.richTextMergeFieldInfo`.
public struct RichMergeFieldAttachmentInfo: Hashable, Sendable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

public enum NSDeltaCodecError: Error, Equatable, CustomStringConvertible {
    case mergeFieldNotEditable(index: Int)

    public var description: String {
        switch self {
        case .mergeFieldNotEditable(let i):
            "Op \(i) is a mergeField embed. This document was decoded without merge-field authoring enabled, so it cannot reach this editor — pass `allowingMergeFields: true` to `decode` if the host app means to allow it here."
        }
    }
}

/// An `NSTextAttachment` that always displays at a size fitting the text container's current
/// line fragment width, preserving the image's aspect ratio — a real bug hands-on testing found:
/// a plain `NSTextAttachment` with no `bounds` set falls back to the image's own pixel
/// dimensions *interpreted as points*, since a `PlatformImage` decoded straight from JPEG bytes
/// (no @2x/@3x naming) reports `scale == 1`. A ~2000-pixel-wide phone photo then renders as a
/// ~2000-*point*-wide attachment, wildly overflowing any reading-width text column, regardless
/// of how small the underlying file has already been downscaled for upload.
public final class FittedImageTextAttachment: NSTextAttachment {
    override public func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return super.attachmentBounds(for: textContainer, proposedLineFragment: lineFrag, glyphPosition: position, characterIndex: charIndex)
        }
        let maxWidth = max(lineFrag.width, 1)
        let width = min(image.size.width, maxWidth)
        let height = width * (image.size.height / image.size.width)
        return CGRect(x: 0, y: 0, width: width, height: height)
    }
}

/// An `NSTextAttachment` rendering a `mergeField` embed as a small rounded pill labeled with
/// its literal field name (e.g. `"viewer.firstName"`), never a resolved value — resolution is
/// always a host-app, read-time concern (see `Vocabulary.vocabularyViolations(allowingMergeFields:)`'s
/// doc comment), so the editor always shows the exact string that will round-trip, letting an
/// author see precisely which field they inserted. Inline, not block-level, unlike
/// `FittedImageTextAttachment` — a merge field sits inside running text ("Dear {name},"), so
/// this attachment carries no forced-newline invariant of its own.
public final class MergeFieldTextAttachment: NSTextAttachment {
    public init(name: String) {
        super.init(data: nil, ofType: nil)
        image = Self.pillImage(name: name)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MergeFieldTextAttachment does not support NSCoding")
    }

    private static func pillImage(name: String) -> PlatformImage {
        let font = PlatformFont.preferredFont(forTextStyle: .footnote)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: PlatformColor.richTextMergeFieldPillText,
        ]
        let textSize = (name as NSString).size(withAttributes: attributes)
        let horizontalPadding: CGFloat = 8
        let verticalPadding: CGFloat = 3
        let size = CGSize(width: textSize.width + horizontalPadding * 2, height: textSize.height + verticalPadding * 2)

        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: size.height / 2)
            PlatformColor.richTextMergeFieldPillFill.setFill()
            path.fill()
            (name as NSString).draw(
                in: CGRect(x: horizontalPadding, y: verticalPadding, width: textSize.width, height: textSize.height),
                withAttributes: attributes
            )
        }
        #elseif canImport(AppKit)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = CGRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: size.height / 2, yRadius: size.height / 2)
        PlatformColor.richTextMergeFieldPillFill.setFill()
        path.fill()
        (name as NSString).draw(
            in: CGRect(x: horizontalPadding, y: verticalPadding, width: textSize.width, height: textSize.height),
            withAttributes: attributes
        )
        image.unlockFocus()
        return image
        #endif
    }

    override public func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        guard let image else {
            return super.attachmentBounds(for: textContainer, proposedLineFragment: lineFrag, glyphPosition: position, characterIndex: charIndex)
        }
        // Nudged down slightly so the pill optically centers on the surrounding text's
        // baseline instead of sitting on it — a plain 0-origin attachment (the image's own
        // bottom-left at the baseline) reads as floating high relative to lowercase text.
        return CGRect(x: 0, y: -3, width: image.size.width, height: image.size.height)
    }
}

extension PlatformColor {
    fileprivate static var richTextMergeFieldPillFill: PlatformColor {
        #if canImport(UIKit)
        UIColor.systemBlue.withAlphaComponent(0.15)
        #elseif canImport(AppKit)
        NSColor.systemBlue.withAlphaComponent(0.15)
        #endif
    }

    fileprivate static var richTextMergeFieldPillText: PlatformColor {
        #if canImport(UIKit)
        UIColor.systemBlue
        #elseif canImport(AppKit)
        NSColor.systemBlue
        #endif
    }
}

/// Converts a whole Delta (text and image ops together) to and from an `NSAttributedString`.
///
/// Two design choices worth being explicit about — see `docs/ARCHITECTURE.md`:
///
/// - **No segmentation.** Images are embedded as real `NSTextAttachment`s directly in one
///   continuous string, rather than being split out into a separate view interleaved with text
///   editors: `UITextView` displays a text attachment inline without issue, so there is nothing
///   to gain from a segmented document structure whose only purpose would be giving a cursor
///   above/below a *non-inline* image — inline attachments don't have that problem.
/// - **The block-level image invariants are still real.** An image must be preceded and followed
///   by a bare `\n` in the *Delta*, even though it is visually inline in the buffer. `encode`
///   restores a missing newline rather than ever producing an invalid Delta; the live editor
///   (`RichTextEditorModel`) additionally guards the common edit paths so this is rarely reached.
public enum NSDeltaCodec {

    // MARK: Decode

    /// - Parameter image: supplies the already-cached image for a key, synchronously. Decode
    ///   never touches the network or the disk itself — callers (the real editor) pre-warm
    ///   `ImageStore` first (see `ImageStore.prefetch(keys:)`) rather than block decode on a
    ///   fetch; tests pass a stub. A `nil` result still produces a correctly-tagged attachment
    ///   with no visible image, so round-trip correctness never depends on image bytes existing.
    /// - Parameter allowingMergeFields: a `mergeField` embed is not authorable by default (see
    ///   `Vocabulary.vocabularyViolations(allowingMergeFields:)`) — decode mirrors that by
    ///   throwing on one unless the caller explicitly opts in, which a host app should do only
    ///   for the specific document types it wants merge-field authoring on.
    public static func decode(
        _ ops: [Op],
        image: (String) -> PlatformImage?,
        allowingMergeFields: Bool = false
    ) throws -> NSMutableAttributedString {
        let result = NSMutableAttributedString()

        for (index, op) in ops.enumerated() {
            switch op.insert {
            case .embed(.mergeField(let name)):
                guard allowingMergeFields else {
                    throw NSDeltaCodecError.mergeFieldNotEditable(index: index)
                }
                result.append(mergeFieldAttachmentRun(name: name))

            case .embed(.image(let key)):
                var alt: String?
                if case .string(let value)? = op.attributes?["alt"] { alt = value }
                result.append(attachmentRun(key: key, alt: alt, image: image(key)))

            case .text(let string):
                let inlineAttributes = op.attributes?.filter { Vocabulary.inlineAttributes.contains($0.key) }
                let blockAttributes = op.attributes?.filter { Vocabulary.blockAttributes.contains($0.key) }
                let token = (blockAttributes?.isEmpty ?? true) ? nil : BlockToken(attributes: blockAttributes!)

                var buffer = ""
                var bufferIsNewlines = false
                func flush() {
                    guard !buffer.isEmpty else { return }
                    result.append(piece(buffer, isNewlines: bufferIsNewlines, inline: inlineAttributes, token: token))
                    buffer = ""
                }
                for character in string {
                    let isNewline = character == "\n"
                    if isNewline != bufferIsNewlines {
                        flush()
                        bufferIsNewlines = isNewline
                    }
                    buffer.append(character)
                }
                flush()
            }
        }

        applyVisualBlockStyling(result)
        return result
    }

    /// Inline, unlike `attachmentRun(key:alt:image:)` — a merge field carries no
    /// forced-newline/terminator run of its own.
    private static func mergeFieldAttachmentRun(name: String) -> NSAttributedString {
        let attachment = MergeFieldTextAttachment(name: name)
        let run = NSMutableAttributedString(attachment: attachment)
        run.addAttribute(
            .richTextMergeFieldInfo,
            value: RichMergeFieldAttachmentInfo(name: name),
            range: NSRange(location: 0, length: run.length)
        )
        return run
    }

    private static func attachmentRun(key: String, alt: String?, image: PlatformImage?) -> NSAttributedString {
        let attachment = FittedImageTextAttachment()
        attachment.image = image
        let run = NSMutableAttributedString(attachment: attachment)
        run.addAttribute(
            .richTextImageInfo,
            value: RichImageAttachmentInfo(key: key, alt: alt),
            range: NSRange(location: 0, length: run.length)
        )
        return run
    }

    private static func piece(
        _ text: String,
        isNewlines: Bool,
        inline: [String: AttributeValue]?,
        token: BlockToken?
    ) -> NSAttributedString {
        guard !isNewlines else {
            let run = NSMutableAttributedString(string: text)
            if let token {
                // Applied per character: a valid document never puts a block attribute on a
                // multi-newline run, but this keeps the invariant true by construction anyway.
                for offset in 0..<run.length {
                    run.addAttribute(.richTextBlockToken, value: token, range: NSRange(location: offset, length: 1))
                }
            }
            return run
        }

        let attributes = inlineNSAttributes(from: inline)
        return NSAttributedString(string: text, attributes: attributes)
    }

    /// A baseline font and text color are applied to **every** run, formatted or not — not
    /// just the ones with an inline mark. Without an explicit `.foregroundColor`, a run decoded
    /// straight from Delta text renders in whatever color a bare `NSAttributedString` happens to
    /// default to, and on a dark background that is indistinguishable from invisible: keystrokes
    /// land (the dirty flag and the read view both confirm real content), the buffer is correct,
    /// but nothing is visible while editing. Found by hands-on device testing.
    private static func inlineNSAttributes(from inline: [String: AttributeValue]?) -> [NSAttributedString.Key: Any] {
        let isBold = inline?["bold"] == .bool(true)
        let isItalic = inline?["italic"] == .bool(true)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont(bold: isBold, italic: isItalic),
            .foregroundColor: PlatformColor.richTextLabel,
        ]

        if inline?["underline"] == .bool(true) {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if inline?["strike"] == .bool(true) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if case .string(let urlString)? = inline?["link"], let url = URL(string: urlString) {
            attributes[.link] = url
        }
        return attributes
    }

    // MARK: Encode

    /// `encode(decode(d)) == d`, byte-identical, unreduced by the fact that images flow through
    /// this codec alongside text.
    public static func encode(_ text: NSAttributedString) -> [Op] {
        var ops: [Op] = []
        var buffer = ""
        var bufferAttributes: [String: AttributeValue]?

        func flushText() {
            guard !buffer.isEmpty else { return }
            ops.append(Op(insert: .text(buffer), attributes: bufferAttributes))
            buffer = ""
        }

        // Walked by Swift `Character` (grapheme cluster), not raw UTF-16 code unit: a code
        // unit at a time corrupts anything outside the BMP (most emoji included) by splitting
        // a surrogate pair into two invalid standalone scalars. `utf16Offset` is what NSString
        // attribute lookups still need, since `NSAttributedString` indexes in UTF-16.
        //
        // `awaitingImageTerminator` is the self-healing half of the block-level image
        // invariant: an ordinary edit in a continuous `UITextView` can trivially put text
        // right after an attachment on the same line (there is no segmentation boundary to
        // stop it, since images live inline in this same continuous string). Rather than let
        // that reach `vocabularyViolations()` as `imageNotFollowedByNewline`, a missing terminator is
        // inserted here — content is added, never dropped, so this can never lose text.
        var utf16Offset = 0
        var awaitingImageTerminator = false
        for character in text.string {
            let charUTF16Length = String(character).utf16.count
            defer { utf16Offset += charUTF16Length }

            if awaitingImageTerminator {
                awaitingImageTerminator = false
                if character != "\n" {
                    ops.append(.text("\n"))
                }
            }

            // A merge-field attachment character: emit the op directly from the tagged field
            // name. Inline, unlike an image — no terminator newline is forced, since a merge
            // field sits inside running text rather than starting its own line.
            if character == "\u{FFFC}",
               let info = text.attribute(.richTextMergeFieldInfo, at: utf16Offset, effectiveRange: nil) as? RichMergeFieldAttachmentInfo {
                flushText()
                ops.append(.mergeField(info.name))
                bufferAttributes = nil
                continue
            }

            // An attachment character: emit the image op directly from the tagged info, never
            // from the loaded image.
            if character == "\u{FFFC}",
               let info = text.attribute(.richTextImageInfo, at: utf16Offset, effectiveRange: nil) as? RichImageAttachmentInfo {
                if !buffer.isEmpty, !buffer.hasSuffix("\n") { buffer.append("\n") }
                flushText()
                ops.append(.image(info.key, alt: info.alt))
                bufferAttributes = nil
                awaitingImageTerminator = true
                continue
            }

            let isNewline = character == "\n"
            let attributes: [String: AttributeValue]?
            if isNewline {
                // An image's terminator is always plain, matching the existing codec's own
                // posture — a block attribute riding on it is dropped, never round-tripped —
                // which is already true here since a fresh `bufferAttributes = nil` was just
                // set and this newline was the very next character.
                let token = text.attribute(.richTextBlockToken, at: utf16Offset, effectiveRange: nil) as? BlockToken
                attributes = token?.attributes
            } else {
                attributes = inlineAttributes(of: text, at: utf16Offset)
            }
            let normalized = (attributes?.isEmpty ?? true) ? nil : attributes

            if normalized != bufferAttributes {
                flushText()
                bufferAttributes = normalized
            } else if isNewline, normalized != nil, buffer.hasSuffix("\n") {
                // Two consecutive newlines carrying the identical, non-empty block token must
                // never merge into one op spanning both — `vocabularyViolations()` correctly
                // rejects that as ambiguous which line the attribute terminates. Real case this
                // fixes: an empty list item adjacent to another item of the same kind (nothing
                // but the newline itself between them), which the `AttributedString` codec never
                // has to handle since a live list line there always carries at least its literal
                // marker text — a property this inline-attachment design's lines don't share.
                flushText()
                bufferAttributes = normalized
            }
            buffer.append(character)
        }
        if awaitingImageTerminator { ops.append(.text("\n")) }
        flushText()

        // Quill terminates every document with a newline. A live `UITextView` has no such
        // guarantee mid-edit — the ordinary state of "typed a line, haven't pressed Return yet"
        // legitimately has no trailing "\n" — so this is normalized here rather than ever
        // surfacing as `integrityFailure`. Found by hands-on testing: without this, a
        // perfectly ordinary mid-typing document tripped the vocabulary check on every save.
        if ops.last?.textContent.hasSuffix("\n") != true {
            ops.append(.text("\n"))
        }

        // `.coalesced()` merges adjacent ops with identical attributes — including, unhelpfully,
        // two adjacent single-newline ops that both carry the same block token (exactly the
        // "empty list item next to another one" case this method already keeps apart during the
        // walk above). Un-merge just that case rather than changing `coalesced()`'s general,
        // deliberately-faithful behavior.
        return Self.splittingAmbiguousBlockRuns(Delta(ops: ops).coalesced()).ops
    }

    /// Splits a text op back into one-newline-each ops wherever coalescing merged more than one
    /// newline under a single block (`header`/`list`) attribute — `vocabularyViolations()`
    /// correctly rejects such a run as ambiguous about which line it terminates.
    private static func splittingAmbiguousBlockRuns(_ delta: Delta) -> Delta {
        var result: [Op] = []
        for op in delta.ops {
            guard case .text(let string) = op.insert, string.count > 1,
                  let attributes = op.attributes,
                  Vocabulary.blockAttributes.contains(where: { attributes[$0] != nil }),
                  string.allSatisfy({ $0 == "\n" })
            else {
                result.append(op)
                continue
            }
            for _ in string {
                result.append(Op(insert: .text("\n"), attributes: attributes))
            }
        }
        return Delta(ops: result)
    }

    /// Reads the vocabulary's inline marks off one character's attributes.
    ///
    /// Headers are rendered with a larger font (see `applyVisualBlockStyling`) but never with
    /// an added bold trait the text did not already carry, precisely so this check — symbolic
    /// traits only, never point size — cannot mistake "is a heading" for "is bold".
    private static func inlineAttributes(of text: NSAttributedString, at index: Int) -> [String: AttributeValue]? {
        var attributes: [String: AttributeValue] = [:]
        let allAttrs = text.attributes(at: index, effectiveRange: nil)

        if let font = allAttrs[.font] as? PlatformFont {
            let traits = font.fontDescriptor.symbolicTraits
            #if canImport(UIKit)
            if traits.contains(.traitBold) { attributes["bold"] = .bool(true) }
            if traits.contains(.traitItalic) { attributes["italic"] = .bool(true) }
            #elseif canImport(AppKit)
            if traits.contains(.bold) { attributes["bold"] = .bool(true) }
            if traits.contains(.italic) { attributes["italic"] = .bool(true) }
            #endif
        }
        if let style = allAttrs[.underlineStyle] as? Int, style != 0 { attributes["underline"] = .bool(true) }
        if let style = allAttrs[.strikethroughStyle] as? Int, style != 0 { attributes["strike"] = .bool(true) }
        if let url = allAttrs[.link] as? URL { attributes["link"] = .string(url.absoluteString) }
        else if let urlString = allAttrs[.link] as? String { attributes["link"] = .string(urlString) }

        return attributes.isEmpty ? nil : attributes
    }

    // MARK: - Visual block styling (headers, lists) — decoration only, never read by encode

    /// Applies `NSParagraphStyle`/`NSTextList` for `list`, and a larger font size for `header`,
    /// across each paragraph, deriving both from `richTextBlockToken` — never the other way
    /// around. Also reconciles `NSTextList` instance identity: consecutive paragraphs of the
    /// same list kind share one `NSTextList` so they number continuously; a non-list paragraph
    /// (or a change of kind) breaks the chain, matching `ordered-list-restart`'s semantics.
    ///
    /// Font size is adjusted in place on whatever font a run already carries — never replaced
    /// wholesale — so a genuinely bold/italic word inside a header keeps that trait visually
    /// and at `encode`, while a header with no inline emphasis is not made to falsely look
    /// (and encode) as bold.
    public static func applyVisualBlockStyling(_ text: NSMutableAttributedString) {
        text.beginEditing()
        defer { text.endEditing() }

        let string = text.string as NSString
        let length = string.length
        var paragraphStart = 0
        var previousListKind: String?
        var previousList: NSTextList?
        var index = 0

        while index < length {
            guard string.character(at: index) == 0x0A else { index += 1; continue }
            defer { paragraphStart = index + 1; index += 1 }

            let token = text.attribute(.richTextBlockToken, at: index, effectiveRange: nil) as? BlockToken
            let paragraphRange = NSRange(location: paragraphStart, length: index - paragraphStart)

            if case .string(let kind)? = token?.attributes["list"] {
                let list: NSTextList
                if previousListKind == kind, let reused = previousList {
                    list = reused
                } else {
                    list = NSTextList(markerFormat: kind == "ordered" ? .decimal : .disc, options: 0)
                }
                let style = NSMutableParagraphStyle()
                style.textLists = [list]
                style.headIndent = 28
                style.firstLineHeadIndent = 0
                text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: paragraphStart, length: paragraphRange.length + 1))
                previousListKind = kind
                previousList = list
            } else {
                previousListKind = nil
                previousList = nil
                text.removeAttribute(.paragraphStyle, range: NSRange(location: paragraphStart, length: paragraphRange.length + 1))
            }

            // Always resized, every pass, to an absolute target derived from the body font's
            // own point size — never from whatever size a run currently happens to carry. A
            // real bug hands-on testing found: computing the new size as `current * scale`
            // made this non-idempotent, since every call re-scaled whatever the *previous*
            // call had already produced. Toggling Header 1 on then back to Body left text
            // stuck at 1.65x forever (no header token means no resize *at all*, so it never
            // came back down), and toggling between Header 1 and Header 2 repeatedly compounded
            // 1.65x and 1.3x on top of each other instead of landing on one or the other.
            if paragraphRange.length > 0 {
                let scale: CGFloat
                if case .int(let level)? = token?.attributes["header"] {
                    // Matches DeltaRenderer's read-path scale exactly: .title/.title2 against
                    // .body is ~28/17 and ~22/17 at the default Dynamic Type size.
                    scale = level == 1 ? 1.65 : 1.3
                } else {
                    scale = 1.0
                }
                resizeFonts(in: text, range: paragraphRange, scale: scale)
            }
        }
    }

    private static func resizeFonts(in text: NSMutableAttributedString, range: NSRange, scale: CGFloat) {
        let targetSize = PlatformFont.preferredFont(forTextStyle: .body).pointSize * scale
        text.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let base = (value as? PlatformFont) ?? PlatformFont.preferredFont(forTextStyle: .body)
            #if canImport(UIKit)
            let resized = PlatformFont(descriptor: base.fontDescriptor, size: targetSize)
            #elseif canImport(AppKit)
            let resized = PlatformFont(descriptor: base.fontDescriptor, size: targetSize) ?? base
            #endif
            text.addAttribute(.font, value: resized, range: subrange)
        }
    }

    private static func bodyFont(bold: Bool, italic: Bool) -> PlatformFont {
        let base = PlatformFont.preferredFont(forTextStyle: .body)
        var traits: PlatformFont.Descriptor.SymbolicTraits = []
        #if canImport(UIKit)
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        #elseif canImport(AppKit)
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        #endif
        #if canImport(UIKit)
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor
        #elseif canImport(AppKit)
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        #endif
        #if canImport(UIKit)
        return PlatformFont(descriptor: descriptor, size: base.pointSize)
        #elseif canImport(AppKit)
        return PlatformFont(descriptor: descriptor, size: base.pointSize) ?? base
        #endif
    }

    // MARK: - Paste hardening & vocabulary clamping

    /// Every `NSAttributedString.Key` this editor ever legitimately writes. Anything else
    /// reaching the buffer — an arbitrary point size, a foreign paragraph style riding along on
    /// a paste, background color, kerning, whatever a rogue programmatic mutation might add — is
    /// outside the vocabulary and must never survive.
    private static let allowedAttributeKeys: Set<NSAttributedString.Key> = [
        .font, .foregroundColor, .underlineStyle, .strikethroughStyle, .link,
        .paragraphStyle, .attachment, .richTextBlockToken, .richTextImageInfo, .richTextMergeFieldInfo,
    ]

    private static func symbolicTraits(of font: PlatformFont?) -> (bold: Bool, italic: Bool) {
        guard let font else { return (false, false) }
        let traits = font.fontDescriptor.symbolicTraits
        #if canImport(UIKit)
        return (traits.contains(.traitBold), traits.contains(.traitItalic))
        #elseif canImport(AppKit)
        return (traits.contains(.bold), traits.contains(.italic))
        #endif
    }

    /// Strips a pasted `NSAttributedString` down to exactly this editor's vocabulary — bold,
    /// italic, underline, strike, and link — before it ever reaches the buffer. Everything else
    /// a real paste from Notes or Safari can carry (point size, font family, foreground/
    /// background color, a foreign paragraph style or list, an embedded image) is discarded
    /// outright rather than translated: the bar here is "blocked," not "reinterpreted" —
    /// guessing at a translation (a pasted `<h1>` becoming this
    /// editor's Header 1, a pasted bullet becoming this editor's list) risks silently fabricating
    /// structure the user never actually chose from this app's own toolbar.
    public static func sanitizedForPaste(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let full = NSRange(location: 0, length: source.length)
        guard full.length > 0 else { return result }
        source.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            // Attachments (pasted images, foreign embeds) are dropped entirely — this editor's
            // images only ever arrive through its own upload flow, the only path that can
            // produce a valid `.richTextImageInfo` key.
            guard attrs[.attachment] == nil else { return }
            let substring = source.attributedSubstring(from: range).string
            result.append(NSAttributedString(string: substring, attributes: sanitizedInlineAttributes(from: attrs)))
        }
        return result
    }

    private static func sanitizedInlineAttributes(from attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        let traits = symbolicTraits(of: attrs[.font] as? PlatformFont)
        var result: [NSAttributedString.Key: Any] = [
            .font: bodyFont(bold: traits.bold, italic: traits.italic),
            .foregroundColor: PlatformColor.richTextLabel,
        ]
        if let style = attrs[.underlineStyle] as? Int, style != 0 {
            result[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if let style = attrs[.strikethroughStyle] as? Int, style != 0 {
            result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let url = attrs[.link] as? URL {
            result[.link] = url
        } else if let urlString = attrs[.link] as? String, let url = URL(string: urlString) {
            result[.link] = url
        }
        return result
    }

    /// The defensive backstop half of vocabulary enforcement: clamps every attribute in `range` down to the
    /// vocabulary, for whatever slips past paste interception — a programmatic mutation, a
    /// future code path that doesn't go through `sanitizedForPaste`. Always reruns
    /// `applyVisualBlockStyling` on the whole document afterward — not just when `range` has
    /// attributes to scan — for two reasons: a `richTextBlockToken` that survives the clamp must
    /// still render its real header size/list marker (rather than the plain body size the
    /// font-snap below would otherwise leave it at), and a *deletion* (a pure character removal,
    /// where the post-edit `range` UIKit reports is legitimately empty — there is nothing new to
    /// scan for disallowed attributes) can still change which paragraphs are now adjacent, which
    /// is exactly when `NSTextList` instance-sharing needs recomputing. A real bug found by
    /// hands-on testing: gating the whole function (including this call) on `range.length > 0`
    /// meant deleting an interrupting paragraph between two ordered lists never renumbered them,
    /// since every character-deleting edit reports a zero-length post-edit range.
    public static func clampToVocabulary(_ text: NSMutableAttributedString, range: NSRange) {
        if range.length > 0, range.location >= 0, NSMaxRange(range) <= text.length {
            text.enumerateAttributes(in: range, options: []) { attrs, subrange, _ in
                for key in attrs.keys where !allowedAttributeKeys.contains(key) {
                    text.removeAttribute(key, range: subrange)
                }
                text.addAttribute(.foregroundColor, value: PlatformColor.richTextLabel, range: subrange)
                let traits = symbolicTraits(of: attrs[.font] as? PlatformFont)
                text.addAttribute(.font, value: bodyFont(bold: traits.bold, italic: traits.italic), range: subrange)
            }
        }
        applyVisualBlockStyling(text)
    }
}

/// The `NSTextStorageDelegate` backstop that clamps every attribute change to the vocabulary
/// via `NSDeltaCodec.clampToVocabulary`, for whatever slips past paste interception. `NSTextStorage.delegate` is a weak/unowned reference;
/// the owner (the live editor) must keep a strong reference to one instance alive for as long as
/// it's attached to a text view's storage.
public final class VocabularyTextStorageDelegate: NSObject, NSTextStorageDelegate {
    /// How many times UIKit invoked this delegate for one triggering edit — guard-suppressed
    /// invocations included. Exposed only so `RichTextCoreTests` can confirm the re-entrancy
    /// guard actually *suppresses* the recursive invocations `clampToVocabulary`'s own attribute
    /// mutations would otherwise cause (`callbackInvocationCount` > 1), rather than merely
    /// observing that clamping happens to work once.
    public private(set) var callbackInvocationCount = 0
    /// How many times `clampToVocabulary` actually ran — should always be exactly 1 per
    /// triggering edit, regardless of how many nested `didProcessEditing` calls its own
    /// mutations cause.
    public private(set) var clampInvocationCount = 0
    /// Not `private`: `RichTextCoreTests` sets this directly to simulate genuine reentrancy
    /// deterministically, rather than relying on whether this SDK version happens to recurse
    /// into the delegate for attribute-only mutations made from inside its own callback (it
    /// doesn't, empirically — Apple's documented pattern for exactly this kind of clamp — but
    /// the guard must hold regardless of that implementation detail).
    var isClamping = false

    override public init() {
        super.init()
    }

    public func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: PlatformTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        callbackInvocationCount += 1
        guard !isClamping else { return }
        isClamping = true
        defer { isClamping = false }
        clampInvocationCount += 1
        NSDeltaCodec.clampToVocabulary(textStorage, range: editedRange)
    }
}

#if canImport(UIKit)
extension UIFont { public typealias Descriptor = UIFontDescriptor }
#elseif canImport(AppKit)
extension NSFont { public typealias Descriptor = NSFontDescriptor }
#endif
