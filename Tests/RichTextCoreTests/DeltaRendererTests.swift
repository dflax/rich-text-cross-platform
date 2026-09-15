import Foundation
import SwiftUI
import Testing
@testable import RichTextCore

/// The read path is the hot path — everyone reads, a handful of admins
/// edit — so it gets proven first, standalone, with no network and no UI.
@Suite("DeltaRenderer")
struct DeltaRendererTests {

    // MARK: - Block structure

    @Test("An empty document renders as one empty paragraph")
    func emptyDocument() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("empty-document").delta)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .paragraph)
        #expect(String(blocks[0].inline.characters).isEmpty)
    }

    /// Three newlines are three lines, not one. A renderer that collapsed them would eat
    /// the blank lines an author deliberately typed.
    @Test("Consecutive newlines each produce their own blank line")
    func blankLines() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("blank-lines").delta)
        #expect(blocks.count == 3)
        #expect(blocks.allSatisfy { $0.kind == .paragraph })
        #expect(blocks.allSatisfy { String($0.inline.characters).isEmpty })
    }

    @Test("A multi-paragraph document splits on newlines, one block per line")
    func multiParagraph() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("multi-paragraph").delta)
        #expect(blocks.map { String($0.inline.characters) } == [
            "Pickup starts at 3:15pm sharp.",
            "Please wait in the marked lane.",
            "Do not block the crosswalk.",
        ])
        #expect(blocks.allSatisfy { $0.kind == .paragraph })
    }

    @Test("Headers take their level from the newline that terminates the line")
    func headers() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("headers").delta)
        #expect(blocks.map(\.kind) == [.header(1), .header(2), .paragraph])
        #expect(String(blocks[0].inline.characters) == "Pickup Instructions")
        #expect(String(blocks[1].inline.characters) == "Afternoon Dismissal")
    }

    @Test("Bullet lists produce bullet blocks")
    func bulletList() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("bullet-list").delta)
        #expect(blocks.count == 3)
        #expect(blocks.allSatisfy { $0.kind == .bullet })
    }

    @Test("Ordered lists carry their own numbering")
    func orderedList() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("ordered-list").delta)
        #expect(blocks.map(\.kind) == [.ordered(1), .ordered(2), .ordered(3)])
    }

    /// Numbering has to restart after an interruption. Getting this wrong produces a list
    /// that reads "1, 2, 3, 4" across a paragraph break, which is silently wrong rather
    /// than visibly broken — the worst kind of rendering bug.
    @Test("An interrupted ordered list restarts its numbering")
    func orderedListRestart() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("ordered-list-restart").delta)
        #expect(blocks.map(\.kind) == [.ordered(1), .ordered(2), .paragraph, .ordered(1), .ordered(2)])
    }

    // MARK: - Images

    @Test("An image-only document is a single image block, with no phantom blank line")
    func imageOnly() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("image-only").delta)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .image(key: "doc-images/8f2a0c11.jpg", alt: nil))
        #expect(String(blocks[0].inline.characters).isEmpty, "An embed must never touch an AttributedString.")
    }

    @Test("Alt text rides through to the block, for accessibilityLabel")
    func imageAlt() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("image-with-alt").delta)
        #expect(blocks[0].kind == .image(key: "doc-images/8f2a0c11.jpg", alt: "Map of the side gate"))
    }

    @Test("A leading image is followed by its text, not by a blank line")
    func leadingImage() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("leading-image").delta)
        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .image(key: "doc-images/map.jpg", alt: "Map of the side gate"))
        #expect(blocks[1].kind == .paragraph)
        #expect(String(blocks[1].inline.characters) == "Enter through the side gate.")
    }

    @Test("A trailing image is the last block; nothing follows it")
    func trailingImage() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("trailing-image").delta)
        #expect(blocks.count == 2)
        #expect(blocks[1].kind == .image(key: "doc-images/map.jpg", alt: "Map of the side gate"))
    }

    @Test("Two adjacent images render as two blocks with nothing between them")
    func adjacentImages() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("adjacent-images").delta)
        #expect(blocks.map(\.kind) == [
            .paragraph,
            .image(key: "doc-images/first.jpg", alt: nil),
            .image(key: "doc-images/second.jpg", alt: nil),
            .paragraph,
        ])
    }

    /// An image breaks a bulleted region rather than becoming a list item — see the
    /// `blockAttributeOnImageTerminator` rule. The list resumes after it.
    @Test("An image inside a bulleted region interrupts the list without joining it")
    func imageInBulletedRegion() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("image-in-bulleted-region").delta)
        #expect(blocks.map(\.kind) == [
            .bullet,
            .image(key: "doc-images/lane-diagram.jpg", alt: "Diagram of the pickup lane"),
            .bullet,
        ])
    }

    // MARK: - Inline formatting

    @Test("Bold applies to exactly the run it was authored on")
    func inlineBold() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("inline-bold").delta)
        #expect(blocks.count == 1)
        let inline = blocks[0].inline
        #expect(String(inline.characters) == "Enter through the side gate.")

        let bolded = boldedText(in: inline)
        #expect(bolded == "side gate")
    }

    @Test("Every inline mark in the vocabulary reaches the AttributedString")
    func allInlineMarks() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("inline-all-marks").delta)
        let inline = blocks[0].inline

        #expect(boldedText(in: inline) == "boldall four")
        #expect(italicizedText(in: inline) == "italicall four")

        let underlined = inline.runs.filter { $0.underlineStyle != nil }
            .map { String(inline[$0.range].characters) }.joined()
        #expect(underlined == "underlineall four")

        let struck = inline.runs.filter { $0.strikethroughStyle != nil }
            .map { String(inline[$0.range].characters) }.joined()
        #expect(struck == "strikeall four")
    }

    @Test("A link inside a bold span keeps both the link and the bold")
    func linkInsideBold() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("link-inside-bold").delta)
        let inline = blocks[0].inline

        let linked = inline.runs.filter { $0.link != nil }
        #expect(linked.count == 1)
        let run = try #require(linked.first)
        #expect(String(inline[run.range].characters) == "full policy")
        #expect(run.link == URL(string: "https://example.org/policy"))
        #expect(boldedText(in: inline) == "full policy")
    }

    @Test("Special characters and non-ASCII survive rendering intact")
    func specialCharacters() throws {
        let fixture = try FixtureCorpus.named("special-characters")
        let blocks = DeltaRenderer.blocks(from: fixture.delta)
        #expect(blocks.count == 2)
        #expect(String(blocks[0].inline.characters).contains("\"like this\""))
        #expect(String(blocks[0].inline.characters).contains("\\"))
        #expect(String(blocks[1].inline.characters).contains("🚸"))
        #expect(String(blocks[1].inline.characters).contains("日本語"))
    }

    // MARK: - Whole-document coverage

    /// The full-vocabulary comparison document: every element of the vocabulary in one place, so
    /// a side-by-side check against Quill has a single fixture to point at.
    @Test("The full-vocabulary fixture renders every element in the table")
    func fullVocabulary() throws {
        let blocks = DeltaRenderer.blocks(from: try FixtureCorpus.named("full-vocabulary").delta)
        #expect(blocks.map(\.kind) == [
            .header(1),
            .paragraph,
            .image(key: "doc-images/8f2a0c11.jpg", alt: "Map of the side gate"),
            .header(2),
            .bullet,
            .bullet,
            .ordered(1),
            .ordered(2),
            .paragraph,
        ])
        #expect(blocks.map(\.id) == Array(0..<blocks.count), "Block ids must be stable positions.")
    }

    @Test("Rendering never drops a document's text")
    func nothingIsDropped() throws {
        for fixture in FixtureCorpus.all {
            let rendered = DeltaRenderer.blocks(from: fixture.delta)
                .map { String($0.inline.characters) }
                .joined()
            let expected = fixture.delta.plainText.replacingOccurrences(of: "\n", with: "")
            #expect(rendered == expected, "Text lost while rendering \(fixture.name).")
        }
    }

    @Test("The mergeField spike renders as its own block, distinct from text")
    func mergeFieldSpike() throws {
        let fixture = try #require(FixtureCorpus.spike.first { $0.name == "mergefield" })
        let blocks = DeltaRenderer.blocks(from: fixture.delta)
        #expect(blocks.contains { $0.kind == .mergeField(name: "viewer.firstName") })
    }

    // MARK: - Helpers

    private func boldedText(in string: AttributedString) -> String {
        string.runs
            .filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
            .map { String(string[$0.range].characters) }
            .joined()
    }

    private func italicizedText(in string: AttributedString) -> String {
        string.runs
            .filter { $0.inlinePresentationIntent?.contains(.emphasized) == true }
            .map { String(string[$0.range].characters) }
            .joined()
    }
}
