import Foundation
import Testing
@testable import RichTextCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Formatting-constraint enforcement, hardened against paste. Two independent layers, each
/// tested here: `sanitizedForPaste` (the primary control, applied at the point of insertion) and
/// `clampToVocabulary`/`VocabularyTextStorageDelegate` (the defensive backstop for anything that
/// slips past it). See `docs/guides/vocabulary-enforcement.md`.
@Suite("Paste hardening & vocabulary clamping")
struct PasteHardeningTests {

    @Test("sanitizedForPaste keeps only bold/italic/underline/strike/link, discarding everything else")
    func sanitizedForPasteKeepsOnlyVocabulary() {
        let source = NSMutableAttributedString()

        let plain = NSMutableAttributedString(string: "Hello ")
        plain.addAttributes([
            .foregroundColor: PlatformColor.red,
            .backgroundColor: PlatformColor.yellow,
            .font: PlatformFont.systemFont(ofSize: 40),
        ], range: NSRange(location: 0, length: plain.length))
        source.append(plain)

        var boldTraits = PlatformFont.Descriptor.SymbolicTraits()
        #if canImport(UIKit)
        boldTraits.insert(.traitBold)
        let boldDescriptor = PlatformFont.systemFont(ofSize: 12).fontDescriptor.withSymbolicTraits(boldTraits)!
        #elseif canImport(AppKit)
        boldTraits.insert(.bold)
        let boldDescriptor = PlatformFont.systemFont(ofSize: 12).fontDescriptor.withSymbolicTraits(boldTraits)
        #endif
        let bold = NSMutableAttributedString(string: "Bold")
        let style = NSMutableParagraphStyle()
        style.headIndent = 40
        bold.addAttributes([
            .font: PlatformFont(descriptor: boldDescriptor, size: 12) ?? PlatformFont.boldSystemFont(ofSize: 12),
            .paragraphStyle: style,
        ], range: NSRange(location: 0, length: bold.length))
        source.append(bold)

        let link = NSMutableAttributedString(string: "Link")
        link.addAttribute(.link, value: URL(string: "https://example.com")!, range: NSRange(location: 0, length: link.length))
        source.append(link)

        let attachment = PlatformTextAttachment()
        source.append(NSAttributedString(attachment: attachment))
        source.append(NSAttributedString(string: "After"))

        let result = NSDeltaCodec.sanitizedForPaste(source)

        #expect(result.string == "Hello BoldLinkAfter", "Attachment character should be dropped; all other text preserved.")

        let helloRange = NSRange(location: 0, length: 6)
        result.enumerateAttributes(in: helloRange, options: []) { attrs, _, _ in
            #expect(attrs[.backgroundColor] == nil, "Background color must never survive a paste.")
            #expect((attrs[.foregroundColor] as? PlatformColor) == PlatformColor.richTextLabel, "Foreground color must snap to the vocabulary label color.")
            let font = attrs[.font] as? PlatformFont
            #expect(font?.pointSize == PlatformFont.preferredFont(forTextStyle: .body).pointSize, "An arbitrary point size must not survive a paste.")
        }

        let boldRange = NSRange(location: 6, length: 4)
        result.enumerateAttributes(in: boldRange, options: []) { attrs, _, _ in
            #expect(attrs[.paragraphStyle] == nil, "A foreign paragraph style must never survive a paste.")
            let font = attrs[.font] as? PlatformFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            #if canImport(UIKit)
            #expect(traits.contains(.traitBold), "Bold is part of the vocabulary and must survive.")
            #elseif canImport(AppKit)
            #expect(traits.contains(.bold), "Bold is part of the vocabulary and must survive.")
            #endif
        }

        let linkRange = NSRange(location: 10, length: 4)
        result.enumerateAttributes(in: linkRange, options: []) { attrs, _, _ in
            #expect((attrs[.link] as? URL)?.absoluteString == "https://example.com", "A link is part of the vocabulary and must survive.")
        }
    }

    @Test("clampToVocabulary strips a disallowed color, font, and foreign paragraph style constructed directly")
    func clampToVocabularyStripsDisallowedAttributes() {
        let text = NSMutableTextStorageDouble(string: "Test\n")
        let full = NSRange(location: 0, length: text.length)
        let foreignStyle = NSMutableParagraphStyle()
        foreignStyle.headIndent = 99
        text.addAttributes([
            .backgroundColor: PlatformColor.systemPink,
            .foregroundColor: PlatformColor.systemPink,
            .font: PlatformFont.systemFont(ofSize: 72),
            .paragraphStyle: foreignStyle,
        ], range: full)

        NSDeltaCodec.clampToVocabulary(text, range: full)

        var sawAny = false
        text.enumerateAttributes(in: NSRange(location: 0, length: 4), options: []) { attrs, _, _ in
            sawAny = true
            #expect(attrs[.backgroundColor] == nil, "An arbitrary background color must be stripped.")
            #expect(attrs[.paragraphStyle] == nil, "A foreign paragraph style with no backing block token must be stripped.")
            #expect((attrs[.foregroundColor] as? PlatformColor) == PlatformColor.richTextLabel, "Foreground color must snap to the vocabulary label color.")
            let font = attrs[.font] as? PlatformFont
            #expect(font?.pointSize == PlatformFont.preferredFont(forTextStyle: .body).pointSize, "An out-of-vocabulary point size must be snapped back to body size.")
        }
        #expect(sawAny)
    }

    @Test("A header's real richTextBlockToken survives clamping and keeps its correct scaled size")
    func clampToVocabularyPreservesLegitimateHeaderSizing() {
        let text = NSMutableTextStorageDouble(string: "Heading\n")
        let bodySize = PlatformFont.preferredFont(forTextStyle: .body).pointSize
        let full = NSRange(location: 0, length: text.length)
        // A disallowed color riding alongside a *real* header token -- the color must go, but
        // the header's own larger size (derived from the token, not from whatever point size
        // happened to be sitting on the run) must survive.
        text.addAttribute(.foregroundColor, value: PlatformColor.systemPink, range: full)
        text.addAttribute(.richTextBlockToken, value: BlockToken(attributes: ["header": .int(1)]), range: NSRange(location: 7, length: 1))

        NSDeltaCodec.clampToVocabulary(text, range: full)

        let font = text.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        #expect(font.map { abs($0.pointSize - bodySize * 1.65) < 0.01 } == true, "A real header token must still produce its scaled size after clamping.")
        #expect((text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor) == PlatformColor.richTextLabel)
    }

    @Test("VocabularyTextStorageDelegate's re-entrancy guard suppresses a nested invocation while a clamp pass is already running")
    func reentrancyGuardSuppressesRecursion() {
        let storage = NSTextStorage(string: "Hello")
        let delegate = VocabularyTextStorageDelegate()
        storage.delegate = delegate

        // Simulate genuine reentrancy directly and deterministically: `didProcessEditing`
        // arriving again while this delegate's own fixup pass for a prior edit is still on the
        // call stack. (Empirically, this SDK doesn't recurse into the delegate for attribute-only
        // mutations made from inside its own callback — Apple's documented pattern for exactly
        // this kind of clamp — but the guard must hold regardless of that implementation detail.)
        delegate.isClamping = true
        delegate.textStorage(storage, didProcessEditing: [], range: NSRange(location: 0, length: 0), changeInLength: 0)
        #expect(delegate.callbackInvocationCount == 1)
        #expect(delegate.clampInvocationCount == 0, "While already clamping, a nested invocation must be a no-op, not a second clamp pass.")

        delegate.isClamping = false
        storage.addAttribute(.backgroundColor, value: PlatformColor.systemPink, range: NSRange(location: 0, length: storage.length))
        #expect(delegate.callbackInvocationCount == 2)
        #expect(delegate.clampInvocationCount == 1, "Once not already clamping, a genuinely new edit must still run the clamp pass.")
        #expect(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil, "The disallowed attribute must still end up stripped on the real edit.")
    }
}

/// A plain `NSMutableAttributedString` stand-in used where a test needs `clampToVocabulary`'s
/// signature but not a real, view-attached `NSTextStorage` — kept as a distinct name only to make
/// each test's intent (storage-attached vs. not) obvious at the call site.
private typealias NSMutableTextStorageDouble = NSMutableAttributedString

#if canImport(UIKit)
private typealias PlatformTextAttachment = NSTextAttachment
#elseif canImport(AppKit)
private typealias PlatformTextAttachment = NSTextAttachment
#endif
