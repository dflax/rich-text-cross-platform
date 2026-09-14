import Foundation
import Testing
@testable import RichTextCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// `NSTextList` instance identity, reconciled by `NSDeltaCodec.applyVisualBlockStyling` — see
/// `docs/PRD-uikit-comparison-editor.md` §2/Testing. This is a rendering-quality concern, not a
/// round-trip one: `encode` never reads `NSTextList` at all, only `richTextBlockToken`, so a
/// bug here could never show up in `NSDeltaCodecTests` and needs its own coverage.
@Suite("NSTextList instance identity and renumbering")
struct NSListReconciliationTests {

    /// The `NSTextList` a paragraph's terminating `\n` carries, or `nil`.
    private func list(in text: NSAttributedString, atParagraphEndingAt newlineIndex: Int) -> NSTextList? {
        let style = text.attribute(.paragraphStyle, at: newlineIndex, effectiveRange: nil) as? NSParagraphStyle
        return style?.textLists.first
    }

    /// Indices of every `\n` in the string, in order — one per paragraph.
    private func newlineIndices(in text: NSAttributedString) -> [Int] {
        let string = text.string as NSString
        var indices: [Int] = []
        for i in 0..<string.length where string.character(at: i) == 0x0A { indices.append(i) }
        return indices
    }

    @Test("An unbroken run of ordered paragraphs shares one NSTextList instance")
    func sequentialOrderedParagraphsShareOneList() throws {
        let delta = try FixtureCorpus.named("ordered-list").delta
        let decoded = try NSDeltaCodec.decode(delta.ops, image: { _ in nil })
        let newlines = newlineIndices(in: decoded)
        #expect(newlines.count >= 2)

        let lists = newlines.map { list(in: decoded, atParagraphEndingAt: $0) }
        #expect(lists.allSatisfy { $0 != nil }, "Every line of an ordered-list fixture must carry a list.")
        let first = try #require(lists.first!)
        for candidate in lists.dropFirst() {
            #expect(candidate === first, "Consecutive ordered paragraphs must share one NSTextList instance to number continuously.")
        }
    }

    @Test("An interrupting non-list paragraph restarts numbering with a new NSTextList instance")
    func interruptingParagraphRestartsTheList() throws {
        let delta = try FixtureCorpus.named("ordered-list-restart").delta
        let decoded = try NSDeltaCodec.decode(delta.ops, image: { _ in nil })
        let newlines = newlineIndices(in: decoded)

        // Fixture shape: "First"(ordered), "Second"(ordered), interrupting prose(none),
        // "Restarted at one"(ordered), "Then two"(ordered).
        let lists = newlines.map { list(in: decoded, atParagraphEndingAt: $0) }
        #expect(lists.count == 5, "Expected 5 lines (2 ordered + 1 interrupting prose containing its own newline + 2 ordered); got \(lists.count).")

        let firstRun = [lists[0], lists[1]]
        #expect(firstRun[0] != nil && firstRun[0] === firstRun[1], "First and Second must share a list instance.")

        // The interrupting paragraph carries no list at all.
        let interrupting = lists[2]
        #expect(interrupting == nil, "The interrupting paragraph must not carry a list.")

        let secondRun = [lists[3], lists[4]]
        #expect(secondRun[0] != nil && secondRun[0] === secondRun[1], "Restarted-at-one and Then-two must share a list instance.")

        #expect(firstRun[0] !== secondRun[0], "The restarted run must be a distinct NSTextList instance from the first run, or it would number 3/4 instead of restarting at 1.")
    }

    @Test("Two adjacent bullet lines share a list instance; the trailing plain paragraph does not")
    func bulletListSharesInstanceExcludingTrailingProse() throws {
        let delta = try FixtureCorpus.named("bullet-list").delta
        let decoded = try NSDeltaCodec.decode(delta.ops, image: { _ in nil })
        let newlines = newlineIndices(in: decoded)
        let lists = newlines.map { list(in: decoded, atParagraphEndingAt: $0) }
        #expect(lists.count == 3)
        let first = try #require(lists[0])
        #expect(lists[1] === first)
        #expect(lists[2] === first)
    }

    @Test("An image interrupting a bulleted region does not merge the lists across it")
    func imageInterruptingAListDoesNotMergeAcrossIt() throws {
        // "Arrive by 3:10"(bullet), image, "Follow the cones"(bullet) — the image paragraph
        // itself carries no list (images cannot be list items), so per the same restart rule
        // as the ordered-list case, the bulleted line after the image must be a fresh instance,
        // not secretly numbered/grouped with the line before it. Bullets render identically
        // regardless of instance sharing, but the identity must still be correct — a bug here
        // would silently become visible the moment this fixture's bullet became `ordered`.
        let delta = try FixtureCorpus.named("image-in-bulleted-region").delta
        let decoded = try NSDeltaCodec.decode(delta.ops, image: { _ in nil })
        let newlines = newlineIndices(in: decoded)
        // Lines: "Arrive by 3:10"(bullet) / image's own terminator(none) / "Follow the
        // cones"(bullet).
        #expect(newlines.count == 3)
        let lists = newlines.map { list(in: decoded, atParagraphEndingAt: $0) }
        #expect(lists[0] != nil)
        #expect(lists[1] == nil, "An image's terminating newline must never carry a list.")
        #expect(lists[2] != nil)
        #expect(lists[0] !== lists[2], "A bullet run broken by a non-list paragraph (even an image's) must not silently share an instance across the break.")
    }

    /// Regression for a real bug found by hands-on testing (U7, `docs/PRD-uikit-comparison-editor
    /// .md`): every test above decodes a fixture and checks the *static* result, which always
    /// goes through `applyVisualBlockStyling` once at decode time regardless of this bug. Live
    /// editing is different — a plain character deletion (no toolbar action) reports a
    /// zero-length post-edit range to `NSTextStorageDelegate`, and `clampToVocabulary` used to
    /// skip its `applyVisualBlockStyling` call whenever the range was empty, so deleting an
    /// interrupting paragraph between two ordered lists left both runs' stale, separate
    /// `NSTextList` instances untouched — they'd never renumber into one continuous list until
    /// some *other* edit (e.g. a toolbar list toggle) happened to trigger reconciliation again.
    @Test("A live delete of an interrupting paragraph — not just a static decode — merges the two ordered runs into one shared instance via the U5 backstop")
    func liveDeleteOfInterruptingParagraphMergesListsViaBackstop() throws {
        let delta = try FixtureCorpus.named("ordered-list-restart").delta
        let decoded = try NSDeltaCodec.decode(delta.ops, image: { _ in nil })
        let storage = NSTextStorage(attributedString: decoded)
        let vocabularyGuard = VocabularyTextStorageDelegate()
        storage.delegate = vocabularyGuard

        let newlines = newlineIndices(in: storage)
        #expect(newlines.count == 5, "Expected 5 lines (2 ordered + 1 interrupting prose + 2 ordered).")
        let listsBefore = newlines.map { list(in: storage, atParagraphEndingAt: $0) }
        #expect(listsBefore[1] !== listsBefore[3], "Precondition: the two ordered runs start out as distinct instances.")

        // Delete the interrupting (non-list) paragraph entirely, including its own newline —
        // exactly what a live "select the paragraph, delete" edit produces. This is a pure
        // character removal with nothing new to scan for disallowed attributes, the exact case
        // the bug above skipped reconciliation for.
        let interruptingStart = newlines[1] + 1
        let interruptingEnd = newlines[2] + 1
        storage.deleteCharacters(in: NSRange(location: interruptingStart, length: interruptingEnd - interruptingStart))

        let newlinesAfter = newlineIndices(in: storage)
        #expect(newlinesAfter.count == 4, "Expected exactly 4 lines left after deleting the interrupting paragraph.")
        let listsAfter = newlinesAfter.map { list(in: storage, atParagraphEndingAt: $0) }
        #expect(listsAfter.allSatisfy { $0 != nil }, "All four remaining lines are ordered and must carry a list.")
        let first = try #require(listsAfter.first!)
        for candidate in listsAfter.dropFirst() {
            #expect(candidate === first, "Once the interrupting paragraph is deleted live, the two previously-separate ordered runs must merge into one shared NSTextList instance so they renumber continuously — automatically, from the plain deletion edit alone, not only after a toolbar action.")
        }
    }

    @Test("Reconciliation does not affect round-trip output at all")
    func reconciliationIsPurelyVisual() throws {
        // Belt-and-suspenders against the exact failure mode the type's own doc comment warns
        // about: `encode` must never read `NSTextList`/`NSParagraphStyle`.
        let delta = try FixtureCorpus.named("ordered-list-restart").delta
        let decoded = try NSDeltaCodec.decode(delta.ops, image: { _ in nil })
        let reencoded = Delta(ops: NSDeltaCodec.encode(decoded))
        #expect(reencoded == delta)
    }
}
