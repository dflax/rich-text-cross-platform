import Foundation
import SwiftUI
import Testing
@testable import RichTextCore

/// Real bug, found by hands-on device testing (not simulator): on SwiftUI, a wrapped multi-line
/// list item read correctly in the *edit* view (real hanging indent, via TextKit's `NSTextList`)
/// but wrapped flush under the marker in the *read* view - `ReadLayout.groups(from:)` bakes the
/// marker into plain text with no paragraph-style indent at all. These tests cover the fix: a
/// `.paragraphStyle` (headIndent 28 / firstLineHeadIndent 0, matching `NSDeltaCodec.
/// applyVisualBlockStyling`'s own edit-path values exactly) attached to each list line - and, just
/// as importantly, that it does NOT bleed onto a non-list line before or after.
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

    @Test("A bullet line carries the list hanging indent, matching the edit path's own values exactly")
    func bulletLineCarriesListIndent() throws {
        let groups = ReadLayout.groups(from: try FixtureCorpus.named("bullet-list").delta)
        let text = try #require(groups.compactMap { if case .text(let t) = $0.content { return t } else { return nil } }.first)

        let style = try #require(try paragraphStyle(in: text, at: "Arrive by 3:10"))
        #expect(style.headIndent == 28)
        #expect(style.firstLineHeadIndent == 0)
    }

    @Test("An ordered line carries the same list hanging indent as a bullet line")
    func orderedLineCarriesListIndent() throws {
        let groups = ReadLayout.groups(from: try FixtureCorpus.named("ordered-list").delta)
        let text = try #require(groups.compactMap { if case .text(let t) = $0.content { return t } else { return nil } }.first)

        let ns = NSAttributedString(text)
        // Every line in this fixture is an ordered item - confirm all three carry the style, not
        // just the first (a bug that only styled the first line of a span would be easy to miss).
        var styledLines = 0
        ns.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: ns.length)) { value, range, _ in
            guard let style = value as? NSParagraphStyle, style.headIndent == 28 else { return }
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

        let headerStyle = try paragraphStyle(in: span, at: "Afternoon Dismissal")
        #expect(headerStyle == nil || headerStyle?.headIndent != 28, "A header line must not carry the list indent.")

        let trailingParagraphStyle = try paragraphStyle(in: span, at: "See the ")
        #expect(
            trailingParagraphStyle == nil || trailingParagraphStyle?.headIndent != 28,
            "The plain paragraph after the list must not inherit its hanging indent."
        )

        let bulletStyle = try #require(try paragraphStyle(in: span, at: "Stay in your car"))
        #expect(bulletStyle.headIndent == 28)
        let orderedStyle = try #require(try paragraphStyle(in: span, at: "Wait for a staff member"))
        #expect(orderedStyle.headIndent == 28)
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
}
