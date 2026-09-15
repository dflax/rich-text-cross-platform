import Foundation
import Testing
@testable import RichTextCore

/// Guards on the corpus itself.
///
/// Every other round-trip test compares output bytes against a fixture's bytes, so a
/// fixture that is subtly non-canonical would make those tests either impossible to pass or
/// — worse — pass for the wrong reason. These run first in spirit: if the corpus is wrong,
/// nothing downstream means anything.
@Suite("Fixture corpus hygiene")
struct FixtureHygieneTests {

    @Test("The corpus is present and covers the cases the vocabulary needs")
    func corpusIsPresent() throws {
        let names = Set(FixtureCorpus.all.map(\.name))
        #expect(names.count >= 19, "Corpus looks truncated; found \(names.count) fixtures.")

        // The named text edge cases.
        for required in [
            "adjacent-identical-runs", "empty-document", "blank-lines",
            "multi-paragraph", "link-inside-bold",
        ] {
            #expect(names.contains(required), "Missing text edge case fixture: \(required)")
        }

        // The named image edge cases.
        for required in [
            "leading-image", "trailing-image", "adjacent-images",
            "image-only", "image-in-bulleted-region",
        ] {
            #expect(names.contains(required), "Missing image edge case fixture: \(required)")
        }
    }

    /// Re-encoding a fixture must reproduce the file byte for byte.
    ///
    /// This is not circular: the fixtures were hand-authored, so if the encoder disagreed
    /// with them about key order, escaping, or spacing, this fails. It pins the canonical
    /// byte form the whole library's correctness bar is expressed in.
    @Test("Every fixture on disk is already in canonical byte form")
    func fixturesAreCanonicalOnDisk() throws {
        for fixture in FixtureCorpus.all + FixtureCorpus.spike {
            let reencoded = fixture.delta.canonicalJSON()
            #expect(
                reencoded == fixture.canonicalBytes,
                """
                Fixture \(fixture.name) is not canonical on disk.
                  on disk: \(fixture.json)
                  encoded: \(String(decoding: reencoded, as: UTF8.self))
                """
            )
        }
    }

    /// Added after a hand-authored fixture slipped through non-canonical.
    ///
    /// `canonicalJSON()` is deliberately faithful rather than normalizing, so it happily
    /// re-encoded two adjacent unattributed ops that Quill's own `Delta.push` would have
    /// merged. The byte-form check could not see it; the codec round-trip could, and did.
    /// This asserts the property directly so the next one fails here instead.
    @Test("Every fixture is coalesced, the way Quill's own Delta.push leaves a document")
    func fixturesAreCoalesced() throws {
        for fixture in FixtureCorpus.all + FixtureCorpus.spike {
            #expect(
                fixture.delta.isCoalesced,
                """
                Fixture \(fixture.name) has adjacent text ops with identical attributes.
                  on disk:    \(fixture.json)
                  coalesced:  \(fixture.delta.coalesced().canonicalJSONString())
                """
            )
            #expect(fixture.delta.coalesced() == fixture.delta)
        }
    }

    @Test("Coalescing merges across newlines, not just within a line")
    func coalescingCrossesNewlines() throws {
        let uncoalesced = Delta(ops: [.text("a\n"), .text("b\n")])
        #expect(!uncoalesced.isCoalesced)
        #expect(uncoalesced.coalesced().canonicalJSONString() == #"{"ops":[{"insert":"a\nb\n"}]}"#)

        // Differing attributes must not merge.
        let distinct = Delta(ops: [.text("a", ["bold": .bool(true)]), .text("b")])
        #expect(distinct.isCoalesced)
        #expect(distinct.coalesced() == distinct)
    }

    @Test("Every authorable fixture is within the shared vocabulary")
    func fixturesAreWithinVocabulary() throws {
        for fixture in FixtureCorpus.all {
            let violations = fixture.delta.vocabularyViolations()
            #expect(
                violations.isEmpty,
                "Fixture \(fixture.name) violates the vocabulary: \(violations.map(\.description))"
            )
        }
    }

    @Test("The mergeField spike fixture is rejected unless explicitly allowed")
    func mergeFieldIsNotAuthorable() throws {
        let spike = FixtureCorpus.spike
        #expect(!spike.isEmpty, "Expected the mergeField spike fixture to exist.")
        for fixture in spike {
            #expect(
                fixture.delta.vocabularyViolations().contains(where: {
                    if case .mergeFieldNotEnabled = $0 { return true }
                    return false
                }),
                "\(fixture.name) should not be authorable without opting in."
            )
            #expect(fixture.delta.vocabularyViolations(allowingMergeFields: true).isEmpty)
        }
    }

    @Test("Decoding is strict about what it does not understand")
    func decodingRejectsUnsupportedShapes() throws {
        // A retain op — this library stores documents wholesale, never as diffs.
        #expect(throws: DeltaError.retainOrDeleteNotSupported(index: 0)) {
            try Delta.decode(json: Data(#"{"ops":[{"retain":3}]}"#.utf8))
        }
        // An embed type nobody has taught the renderer about. Silently skipping it would
        // lose content, which is exactly the failure this decoder's strictness rules out.
        #expect(throws: DeltaError.unknownEmbed(index: 0, key: "video")) {
            try Delta.decode(json: Data(#"{"ops":[{"insert":{"video":"x"}}]}"#.utf8))
        }
        #expect(throws: DeltaError.missingOps) {
            try Delta.decode(json: Data(#"{"notOps":[]}"#.utf8))
        }
    }

    /// `true` and `1` are both `NSNumber` once JSONSerialization is done with them. If the
    /// decoder gets that wrong, `{"bold":true}` re-encodes as `{"bold":1}` and every
    /// round-trip test fails for a reason that looks nothing like the actual cause.
    @Test("Booleans and integers stay distinct through a decode/encode cycle")
    func booleanAttributesDoNotDegradeToIntegers() throws {
        let json = #"{"ops":[{"insert":"a","attributes":{"bold":true}},{"insert":"\n","attributes":{"header":1}}]}"#
        let delta = try Delta.decode(json: Data(json.utf8))
        #expect(delta.ops[0].attributes?["bold"] == .bool(true))
        #expect(delta.ops[1].attributes?["header"] == .int(1))
        #expect(delta.canonicalJSONString() == json)
    }

    @Test("An empty attributes object is the same as no attributes at all")
    func emptyAttributesNormalizeToNil() throws {
        let withEmpty = try Delta.decode(json: Data(#"{"ops":[{"insert":"a\n","attributes":{}}]}"#.utf8))
        let without = try Delta.decode(json: Data(#"{"ops":[{"insert":"a\n"}]}"#.utf8))
        #expect(withEmpty == without)
        #expect(withEmpty.canonicalJSON() == without.canonicalJSON())
    }

    @Test("Forward slashes in image keys are never escaped")
    func imageKeysWithSlashesSurviveEncoding() throws {
        let delta = Delta(ops: [.image("doc-images/2026/09/a.jpg"), .text("\n")])
        #expect(delta.canonicalJSONString().contains("doc-images/2026/09/a.jpg"))
        #expect(!delta.canonicalJSONString().contains("\\/"))
    }

    /// A rule not obvious from the vocabulary table alone, found while authoring the corpus.
    @Test("An image's terminating newline may not carry a block attribute")
    func imageCannotBeAListItem() throws {
        let json = #"{"ops":[{"insert":{"image":"k"}},{"insert":"\n","attributes":{"list":"bullet"}}]}"#
        let delta = try Delta.decode(json: Data(json.utf8))
        #expect(delta.vocabularyViolations().contains(.blockAttributeOnImageTerminator(index: 0, name: "list")))
    }

    /// The invariant the whole sync design rests on, stated as narrowly as it actually holds.
    ///
    /// A URL baked into a document changes every time it is regenerated, which changes the
    /// bytes, breaks canonicality, and turns the equality-based change check into a source of
    /// phantom conflicts. But the rule is about **image embed values only** — `link`
    /// attributes are legitimately URLs, and a blanket "no URLs" check would reject valid
    /// documents.
    @Test("An image embed always references an object key, never a URL")
    func imageReferencesAreObjectKeys() throws {
        for fixture in FixtureCorpus.all + FixtureCorpus.spike {
            for (index, op) in fixture.delta.ops.enumerated() {
                guard case .embed(.image(let key)) = op.insert else { continue }
                #expect(
                    !Delta.looksLikeURL(key),
                    "Fixture \(fixture.name) op \(index) stores a URL instead of an object key: \(key)"
                )
            }
        }

        for bad in ["https://f005.backblazeb2.com/file/example-bucket/a.jpg",
                    "http://example.org/a.jpg",
                    "data:image/jpeg;base64,/9j/4AAQ"] {
            let delta = Delta(ops: [.image(bad), .text("\n")])
            #expect(
                delta.vocabularyViolations().contains(.imageReferenceIsURL(index: 0, value: bad)),
                "\(bad) should be rejected as a URL."
            )
        }

        // Real object keys must not trip the check, including ones with dots and dashes.
        for good in ["doc-images/8f2a0c11.jpg", "doc-images/2026/09/a.b.c.jpg", "plain.jpg"] {
            let delta = Delta(ops: [.image(good), .text("\n")])
            #expect(delta.vocabularyViolations().isEmpty, "\(good) is a valid key but was rejected.")
        }
    }

    /// Links are URLs and must stay that way — the check above must not touch them.
    @Test("The image-key rule does not reject legitimate link attributes")
    func linksAreUnaffected() throws {
        let fixture = try FixtureCorpus.named("link-inside-bold")
        #expect(fixture.delta.vocabularyViolations().isEmpty)
        #expect(fixture.delta.canonicalJSONString().contains("https://example.org/policy"))
    }

    @Test("An image not followed by a newline is a violation")
    func imagesAreBlockLevel() throws {
        let json = #"{"ops":[{"insert":"before "},{"insert":{"image":"k"}},{"insert":" after\n"}]}"#
        let delta = try Delta.decode(json: Data(json.utf8))
        #expect(delta.vocabularyViolations().contains(.imageNotFollowedByNewline(index: 1)))
    }
}
