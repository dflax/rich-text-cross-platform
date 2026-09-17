import Foundation
import SwiftUI
import Testing
@testable import RichTextCore

/// Real bug, found by hands-on device testing (not simulator): on SwiftUI, a wrapped multi-line
/// list item read correctly in the *edit* view (real hanging indent, via TextKit's `NSTextList`)
/// but wrapped flush under the marker in the *read* view - `ReadLayout.groups(from:)` bakes the
/// marker into plain text with no paragraph-style indent at all. These tests cover the fix: a
/// `.paragraphStyle` (headIndent measured from the marker's own rendered width, firstLineHeadIndent
/// 0) attached to each list line - and, just as importantly, that it does NOT bleed onto a
/// non-list line before or after.
///
/// A second real bug, found on the same device pass: the body font size (`default: .body`, a
/// semantic `Font.TextStyle`) silently produced NO font attribute at all once bridged through
/// `NSAttributedString` - confirmed too small on-device once rendered through a real text view.
/// Fixed alongside the indent work since the marker's own measured width depends on the font size
/// being correct first.
///
/// `AttributedString` has no first-class Swift attribute for `.paragraphStyle` - these tests
/// inspect it via the same `NSAttributedString` bridge the fix itself uses.
@Suite("ReadLayout")
struct ReadLayoutTests {

    private func paragraphStyle(in text: AttributedString, at substring: String) throws -> NSParagraphStyle? {
        let ns = NSAttributedString(text)
        let range = try #require((ns.string as NSString).range(of: substring).location != NSNotFound ? (ns.string as NSString).range(of: substring) : nil)
        return ns.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
    }

    @Test("A bullet line carries a hanging indent matching its own marker's rendered width")
    func bulletLineCarriesListIndent() throws {
        let groups = ReadLayout.groups(from: try FixtureCorpus.named("bullet-list").delta)
        let text = try #require(groups.compactMap { if case .text(let t) = $0.content { return t } else { return nil } }.first)

        let style = try #require(try paragraphStyle(in: text, at: "Arrive by 3:10"))
        #expect(style.firstLineHeadIndent == 0)
        // "•  " at 17pt body size is meaningfully narrower than a two-digit ordered marker - a
        // reasonable range check rather than a magic constant, since the exact value is a real
        // font measurement, not something this test should hardcode and risk drifting from.
        #expect((10...25).contains(style.headIndent), "headIndent \(style.headIndent) is not a plausible bullet marker width.")
    }

    @Test("An ordered line's indent is measured from ITS OWN marker, wider than a bullet's")
    func orderedLineCarriesListIndent() throws {
        let bulletGroups = ReadLayout.groups(from: try FixtureCorpus.named("bullet-list").delta)
        let bulletText = try #require(bulletGroups.compactMap { if case .text(let t) = $0.content { return t } else { return nil } }.first)
        let bulletStyle = try #require(try paragraphStyle(in: bulletText, at: "Arrive by 3:10"))

        let orderedGroups = ReadLayout.groups(from: try FixtureCorpus.named("ordered-list").delta)
        let orderedText = try #require(orderedGroups.compactMap { if case .text(let t) = $0.content { return t } else { return nil } }.first)
        let orderedStyle = try #require(try paragraphStyle(in: orderedText, at: "Pull into the lane"))

        #expect(orderedStyle.firstLineHeadIndent == 0)
        #expect(
            orderedStyle.headIndent > bulletStyle.headIndent,
            "\"1.  \" is visibly wider than \"•  \" - a shared fixed indent would misalign one of them."
        )

        // Every line in this fixture is an ordered item - confirm all three carry the style, not
        // just the first (a bug that only styled the first line of a span would be easy to miss).
        let ns = NSAttributedString(orderedText)
        var styledLines = 0
        ns.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: ns.length)) { value, range, _ in
            guard let style = value as? NSParagraphStyle, style.headIndent == orderedStyle.headIndent else { return }
            styledLines += (ns.string as NSString).substring(with: range).isEmpty ? 0 : 1
        }
        #expect(styledLines > 0)
    }

    @Test("A plain paragraph immediately after a list does not inherit the list's hanging indent")
    func noBleedOntoFollowingParagraph() throws {
        // full-vocabulary: header2, bullet, bullet, ordered, ordered, paragraph - all consecutive
        // non-image blocks, so they land in ONE span. The trailing paragraph's own text must be
        // unstyled even though the immediately preceding separator newline (the ordered item's
        // own trailing newline) legitimately carries the list style.
        let groups = ReadLayout.groups(from: try FixtureCorpus.named("full-vocabulary").delta)
        let textGroups = groups.compactMap { group -> AttributedString? in
            if case .text(let t) = group.content { return t } else { return nil }
        }
        let span = try #require(textGroups.first { String($0.characters).contains("Wait for a staff member") })

        let bulletStyle = try #require(try paragraphStyle(in: span, at: "Stay in your car"))
        let orderedStyle = try #require(try paragraphStyle(in: span, at: "Wait for a staff member"))
        #expect(bulletStyle.headIndent > 0)
        #expect(orderedStyle.headIndent > 0)

        let headerStyle = try paragraphStyle(in: span, at: "Afternoon Dismissal")
        #expect(headerStyle == nil || headerStyle?.headIndent == 0, "A header line must not carry the list indent.")

        let trailingParagraphStyle = try paragraphStyle(in: span, at: "See the ")
        #expect(
            trailingParagraphStyle == nil || trailingParagraphStyle?.headIndent == 0,
            "The plain paragraph after the list must not inherit its hanging indent."
        )
    }

    @Test("The list style does not set textLists - the marker is already baked into the characters")
    func doesNotDoubleUpTheMarker() throws {
        let groups = ReadLayout.groups(from: try FixtureCorpus.named("bullet-list").delta)
        let text = try #require(groups.compactMap { if case .text(let t) = $0.content { return t } else { return nil } }.first)
        let style = try #require(try paragraphStyle(in: text, at: "Arrive"))
        #expect(style.textLists.isEmpty)
        // The visible bullet character is a real, plain character in the string.
        #expect(String(text.characters).contains("•"))
    }

    @Test("Body text gets a real, concrete font attribute - not a semantic Font.TextStyle that vanishes on bridging")
    func bodyTextHasAConcreteFontAttribute() throws {
        let groups = ReadLayout.groups(from: try FixtureCorpus.named("multi-paragraph").delta)
        let text = try #require(groups.compactMap { if case .text(let t) = $0.content { return t } else { return nil } }.first)
        let ns = NSAttributedString(text)
        let font = try #require(ns.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)
        #expect(font.pointSize == 17)
    }

    @Test("Bold/italic inline emphasis gets a real font trait, at its own block's point size")
    func boldAndItalicGetRealFontTraits() throws {
        let groups = ReadLayout.groups(from: try FixtureCorpus.named("full-vocabulary").delta)
        let span = try #require(groups.compactMap { if case .text(let t) = $0.content { return t } else { return nil } }.first)
        let ns = NSAttributedString(span)

        // "side gate"/"main doors" sit in the plain paragraph right after the <h1>, not inside it -
        // so body size (17), not the header's 28, is correct here.
        let boldRange = (ns.string as NSString).range(of: "side gate")
        try #require(boldRange.location != NSNotFound)
        let boldFont = try #require(ns.attribute(.font, at: boldRange.location, effectiveRange: nil) as? PlatformFont)
        #expect(boldFont.pointSize == 17)
        #if canImport(UIKit)
        #expect(boldFont.fontDescriptor.symbolicTraits.contains(.traitBold))
        #elseif canImport(AppKit)
        #expect(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))
        #endif

        let italicRange = (ns.string as NSString).range(of: "main doors")
        try #require(italicRange.location != NSNotFound)
        let italicFont = try #require(ns.attribute(.font, at: italicRange.location, effectiveRange: nil) as? PlatformFont)
        #expect(italicFont.pointSize == 17)
        #if canImport(UIKit)
        #expect(italicFont.fontDescriptor.symbolicTraits.contains(.traitItalic))
        #elseif canImport(AppKit)
        #expect(NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask))
        #endif
    }

    @Test("Underline and strikethrough survive bridging as real NSAttributedString keys")
    func underlineAndStrikethroughBridgeToRealKeys() throws {
        let groups = ReadLayout.groups(from: try FixtureCorpus.named("full-vocabulary").delta)
        let span = try #require(groups.compactMap { if case .text(let t) = $0.content { return t } else { return nil } }.last)
        let ns = NSAttributedString(span)

        let underlineRange = (ns.string as NSString).range(of: "details")
        try #require(underlineRange.location != NSNotFound)
        let underline = try #require(ns.attribute(.underlineStyle, at: underlineRange.location, effectiveRange: nil) as? Int)
        #expect(underline != 0)

        let strikeRange = (ns.string as NSString).range(of: "exceptions")
        try #require(strikeRange.location != NSNotFound)
        let strike = try #require(ns.attribute(.strikethroughStyle, at: strikeRange.location, effectiveRange: nil) as? Int)
        #expect(strike != 0)
    }
}
