import Foundation
import Testing
@testable import RichTextCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// `NSDeltaCodec`'s round-trip obligation is `encode(decode(d)) == d`, byte-identical — and
/// since it carries images through directly rather than relying on a prior segmentation pass,
/// the image fixtures are part of this corpus too, not a separate concern.
@Suite("NSDeltaCodec round trip: encode(decode(d)) == d")
struct NSDeltaCodecTests {

    private func roundTrip(_ delta: Delta, image: (String) -> PlatformImage? = { _ in nil }) throws -> Delta {
        Delta(ops: NSDeltaCodec.encode(try NSDeltaCodec.decode(delta.ops, image: image)))
    }

    @Test("Every authorable fixture round-trips byte-identically, images included")
    func everyFixtureRoundTrips() throws {
        let fixtures = FixtureCorpus.all
        #expect(fixtures.count >= 15, "Expected the full corpus; found \(fixtures.count).")

        for fixture in fixtures {
            let result = try roundTrip(fixture.delta)
            #expect(
                result.canonicalJSON() == fixture.canonicalBytes,
                """
                \(fixture.name) did not round-trip byte-identically.
                  expected: \(fixture.json)
                  actual:   \(result.canonicalJSONString())
                """
            )
        }
    }

    @Test("Headers and lists survive as opaque metadata, never inferred from the rendered font")
    func blockAttributesAreCarriedNotInferred() throws {
        for name in ["headers", "bullet-list", "ordered-list", "ordered-list-restart"] {
            let fixture = try FixtureCorpus.named(name)
            #expect(
                try roundTrip(fixture.delta).canonicalJSON() == fixture.canonicalBytes,
                "\(name) lost its block structure."
            )
        }
    }

    @Test("A header's larger display font is never mistaken for inline bold at encode")
    func headerSizeIsNotBold() throws {
        let fixture = try FixtureCorpus.named("headers")
        let decoded = try NSDeltaCodec.decode(fixture.delta.ops, image: { _ in nil })
        let ops = NSDeltaCodec.encode(decoded)
        for op in ops where op.attributes?["header"] != nil {
            #expect(op.attributes?["bold"] == nil, "A plain header must not pick up a spurious bold attribute.")
        }
    }

    @Test("Every image fixture round-trips, including alt text and surrounding structure")
    func imageFixturesRoundTrip() throws {
        for name in ["image-only", "image-with-alt", "leading-image", "trailing-image", "adjacent-images", "image-in-bulleted-region"] {
            let fixture = try FixtureCorpus.named(name)
            let result = try roundTrip(fixture.delta)
            #expect(
                result.canonicalJSON() == fixture.canonicalBytes,
                "\(name) did not round-trip byte-identically.\n  expected: \(fixture.json)\n  actual:   \(result.canonicalJSONString())"
            )
        }
    }

    @Test("An image round-trips its key correctly even when the image itself fails to load")
    func imageKeySurvivesMissingBytes() throws {
        let delta = try FixtureCorpus.named("image-with-alt").delta
        // `image:` returns nil — simulating an offline cache miss — and the key must still
        // come back exactly, since encode reads the tagged key, never the loaded image.
        let result = try roundTrip(delta, image: { _ in nil })
        #expect(result == delta)
    }

    @Test("Decoding preserves a document's text exactly")
    func decodePreservesText() throws {
        for fixture in FixtureCorpus.all {
            let decoded = try NSDeltaCodec.decode(fixture.delta.ops, image: { _ in nil })
            // NSTextAttachment contributes the replacement character U+FFFC to `.string`,
            // which is not part of the Delta's plain-text projection.
            let withoutAttachments = decoded.string.replacingOccurrences(of: "\u{FFFC}", with: "")
            #expect(withoutAttachments == fixture.delta.plainText, "Text changed decoding \(fixture.name).")
        }
    }

    @Test("The encoder never emits two adjacent text ops with equal attributes")
    func outputIsAlwaysCoalesced() throws {
        for fixture in FixtureCorpus.all {
            let ops = try roundTrip(fixture.delta).ops
            for (first, second) in zip(ops, ops.dropFirst()) {
                let bothText = !first.isEmbed && !second.isEmbed
                #expect(
                    !(bothText && first.attributes == second.attributes),
                    "\(fixture.name) produced adjacent ops with identical attributes — output is not canonical."
                )
            }
        }
    }

    @Test("Round-tripping twice is identical to round-tripping once")
    func roundTripIsIdempotent() throws {
        for fixture in FixtureCorpus.all {
            let once = try roundTrip(fixture.delta)
            let twice = try roundTrip(once)
            #expect(once.canonicalJSON() == twice.canonicalJSON(), "\(fixture.name) is not a fixed point.")
        }
    }

    @Test("A mergeField embed reaching the codec is an error, not something it quietly handles")
    func mergeFieldIsRejected() throws {
        let ops: [Op] = [.text("a\n"), Op(insert: .embed(.mergeField(name: "x")))]
        #expect(throws: NSDeltaCodecError.mergeFieldNotEditable(index: 1)) {
            try NSDeltaCodec.decode(ops, image: { _ in nil })
        }
    }

    @Test("A missing newline after an image is restored rather than producing an invalid Delta")
    func missingImageTerminatorIsRestored() throws {
        // Simulates a live edit that left text directly after an attachment on the same line —
        // the ordinary-typing hazard of embedding images inline introduces exactly this.
        let text = NSMutableAttributedString(string: "before\n")
        let attachment = NSTextAttachment()
        let attachmentRun = NSMutableAttributedString(attachment: attachment)
        attachmentRun.addAttribute(.richTextImageInfo, value: RichImageAttachmentInfo(key: "k.jpg", alt: nil), range: NSRange(location: 0, length: 1))
        text.append(attachmentRun)
        text.append(NSAttributedString(string: "after\n"))

        let ops = NSDeltaCodec.encode(text)
        let violations = Delta(ops: ops).vocabularyViolations()
        #expect(violations.isEmpty, "Expected the encoder to self-heal a missing image terminator; got: \(violations)")
    }

    /// Regression for a real bug found by hands-on testing: an empty bulleted line immediately
    /// followed by another bulleted line — nothing but the two newlines between them — must
    /// never encode as one op spanning both newlines, since that op's own attributes couldn't
    /// say which of the two lines they terminate.
    @Test("Two adjacent same-kind list newlines with nothing between them never merge into one op")
    func adjacentSameKindListNewlinesStaySeparate() throws {
        let text = NSMutableAttributedString(string: "Item 1\n\nItem 2\n")
        let bulletToken = BlockToken(attributes: ["list": .string("bullet")])
        // "Item 1" ends at index 6; the newline at 6 and the empty line's newline at 7 both
        // carry the identical token, with nothing else between them.
        text.addAttribute(.richTextBlockToken, value: bulletToken, range: NSRange(location: 6, length: 1))
        text.addAttribute(.richTextBlockToken, value: bulletToken, range: NSRange(location: 7, length: 1))
        text.addAttribute(.richTextBlockToken, value: bulletToken, range: NSRange(location: 14, length: 1))

        let ops = NSDeltaCodec.encode(text)
        let violations = Delta(ops: ops).vocabularyViolations()
        #expect(violations.isEmpty, "Expected adjacent same-token newlines to stay in separate ops; got: \(violations)")
        for op in ops {
            if op.attributes?["list"] != nil {
                #expect(op.textContent == "\n", "A list-tagged op must carry exactly one newline, got \(op.textContent.debugDescription)")
            }
        }
    }

    /// Regression for a real bug found by hands-on device testing: a document mid-typing (the
    /// last line has no trailing "\n" yet, because the user simply hasn't pressed Return) must
    /// never trip `documentDoesNotEndWithNewline` — `encode` self-heals this exact case, since
    /// Quill terminates every document with a newline but a live `UITextView` has no such
    /// guarantee mid-edit.
    @Test("A document with no trailing newline yet — ordinary mid-typing state — is normalized, not flagged invalid")
    func missingTrailingNewlineIsRestored() throws {
        let text = NSMutableAttributedString(string: "Entry 4")
        let ops = NSDeltaCodec.encode(text)
        #expect(ops.last?.textContent.hasSuffix("\n") == true)
        #expect(Delta(ops: ops).vocabularyViolations().isEmpty)
    }

    /// Regression for the other real bug hands-on testing found: plain, unformatted text decoded
    /// straight from Delta must carry an explicit, visible foreground color — without one, a run
    /// renders however a bare `NSAttributedString` happens to default, which on a dark
    /// background is indistinguishable from invisible even though the buffer is correct.
    @Test("Every decoded run of visible text carries an explicit, non-nil foreground color")
    func everyTextRunHasAnExplicitForegroundColor() throws {
        for fixture in FixtureCorpus.all {
            let decoded = try NSDeltaCodec.decode(fixture.delta.ops, image: { _ in nil })
            let string = decoded.string as NSString
            var index = 0
            while index < decoded.length {
                var range = NSRange(location: 0, length: 0)
                let color = decoded.attribute(.foregroundColor, at: index, effectiveRange: &range)
                // Newlines and attachment characters carry no visible glyph — only ordinary
                // text characters are where the dark-mode invisible-text bug could ever show up.
                let character = string.character(at: index)
                let isVisibleText = character != 0x0A && character != NSTextAttachment.character
                if isVisibleText {
                    #expect(color != nil, "\(fixture.name) has a text run at \(index) with no explicit foreground color.")
                }
                index = range.location + max(range.length, 1)
            }
        }
    }

    /// Regression for a real bug found by hands-on device testing: `applyVisualBlockStyling`
    /// used to compute a header's enlarged font size as `currentSize * scale`, which is only
    /// correct the first time it runs. Toggling Header 1 back to Body removed the block token
    /// but never resized the font back down — nothing there to resize *to* once the header
    /// branch stopped matching — so the paragraph stayed stuck at 1.65x forever. Toggling
    /// between Header 1 and Header 2 repeatedly compounded 1.65x and 1.3x on top of each other
    /// instead of landing on whichever level was last selected.
    @Test("Repeatedly toggling a paragraph's header level always converges to that level's exact size, never compounds")
    func headerToggleFontSizeIsIdempotent() throws {
        let text = NSMutableAttributedString(string: "Heading\n")
        let bodySize = PlatformFont.preferredFont(forTextStyle: .body).pointSize

        func setHeader(_ level: Int?) {
            if let level {
                text.addAttribute(.richTextBlockToken, value: BlockToken(attributes: ["header": .int(level)]), range: NSRange(location: 7, length: 1))
            } else {
                text.removeAttribute(.richTextBlockToken, range: NSRange(location: 7, length: 1))
            }
            NSDeltaCodec.applyVisualBlockStyling(text)
        }

        func fontSize() -> CGFloat {
            (text.attribute(.font, at: 0, effectiveRange: nil) as! PlatformFont).pointSize
        }

        setHeader(1)
        #expect(abs(fontSize() - bodySize * 1.65) < 0.01, "First Header 1 application did not scale to 1.65x body size.")

        setHeader(2)
        #expect(abs(fontSize() - bodySize * 1.3) < 0.01, "Switching Header 1 -> Header 2 compounded instead of landing on 1.3x.")

        setHeader(1)
        setHeader(1)
        #expect(abs(fontSize() - bodySize * 1.65) < 0.01, "Reapplying Header 1 twice in a row compounded past 1.65x.")

        setHeader(nil)
        #expect(abs(fontSize() - bodySize) < 0.01, "Reverting to Body did not reset the font back down from Header 1's size.")
    }

    /// Regression for a real bug found by hands-on device testing: a plain `NSTextAttachment`
    /// with no `bounds` set falls back to the image's own pixel dimensions *interpreted as
    /// points*, since a `PlatformImage` decoded straight from JPEG bytes (no @2x/@3x naming)
    /// reports `scale == 1`. A ~2000-pixel-wide phone photo then rendered as a
    /// ~2000-*point*-wide attachment, wildly overflowing any reading-width text column.
    @Test("A decoded image attachment fits the text container's width instead of rendering at its raw pixel size")
    func decodedImageAttachmentFitsContainerWidth() throws {
        let fixture = try FixtureCorpus.named("image-only")
        #if canImport(UIKit)
        let hugeImage = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1200)).image { context in
            PlatformColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
        }
        #elseif canImport(AppKit)
        let hugeImage = NSImage(size: CGSize(width: 2400, height: 1200))
        hugeImage.lockFocus()
        PlatformColor.red.setFill()
        NSRect(x: 0, y: 0, width: 2400, height: 1200).fill()
        hugeImage.unlockFocus()
        #endif

        let decoded = try NSDeltaCodec.decode(fixture.delta.ops, image: { _ in hugeImage })
        var attachmentRange = NSRange(location: 0, length: 0)
        let attachment = decoded.attribute(.attachment, at: 0, longestEffectiveRange: &attachmentRange, in: NSRange(location: 0, length: decoded.length)) as? FittedImageTextAttachment
        let fitted = try #require(attachment, "Decoded images must use FittedImageTextAttachment, not a plain NSTextAttachment with no bounds.")

        let narrowColumn = CGRect(x: 0, y: 0, width: 320, height: 10000)
        let bounds = fitted.attachmentBounds(for: nil, proposedLineFragment: narrowColumn, glyphPosition: .zero, characterIndex: 0)
        #expect(bounds.width <= 320, "A 2400pt-wide source image must never render wider than its text column.")
        let renderedAspect: CGFloat = bounds.height / bounds.width
        let sourceAspect: CGFloat = 1200.0 / 2400.0
        #expect(abs(renderedAspect - sourceAspect) < 0.01, "Fitting to the column width must preserve the image's aspect ratio.")
    }
}
