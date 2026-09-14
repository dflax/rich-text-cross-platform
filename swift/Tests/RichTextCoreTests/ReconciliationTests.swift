import Foundation
import Testing
@testable import RichTextCore

/// Build Order step 9: the three-way comparison sync rests on.
///
/// Every branch is exercised, including the two that must *not* write. A reconciler that
/// silently picks a winner is exactly the automatic conflict resolution `PRD.md` lists as a
/// Non-Goal, so "all three differ" is asserted to surface rather than resolve.
@Suite("Reconciliation: base/mine/theirs")
struct ReconciliationTests {

    private func bytes(_ text: String) -> Data {
        Delta(ops: [.text(text)]).canonicalJSON()
    }

    private let original = Delta(ops: [.text("Hello\n")]).canonicalJSON()
    private let localEdit = Delta(ops: [.text("Hello, local\n")]).canonicalJSON()
    private let remoteEdit = Delta(ops: [.text("Hello, remote\n")]).canonicalJSON()

    // MARK: - The three branches the PRD names

    @Test("base == theirs, mine moved → push")
    func pushesWhenOnlyLocalChanged() {
        #expect(Reconciler.decide(base: original, mine: localEdit, theirs: original) == .push)
    }

    @Test("base == mine, theirs moved → pull")
    func pullsWhenOnlyRemoteChanged() {
        #expect(Reconciler.decide(base: original, mine: original, theirs: remoteEdit) == .pull)
    }

    @Test("all three differ → conflict, never an automatic winner")
    func conflictsWhenBothChanged() {
        let decision = Reconciler.decide(base: original, mine: localEdit, theirs: remoteEdit)
        #expect(decision == .conflict(.bothEdited))
        // Stated as an assertion rather than a comment: automatic resolution is a Non-Goal,
        // so the conflict branch must never collapse into push or pull.
        #expect(decision != .push)
        #expect(decision != .pull)
    }

    // MARK: - The branches that must cost zero writes

    @Test("base == mine == theirs → in sync, no write on either side")
    func noWriteWhenNothingChanged() {
        #expect(Reconciler.decide(base: original, mine: original, theirs: original) == .inSync)
    }

    @Test("Both sides made the same edit → in sync, not a conflict")
    func convergentEditIsNotAConflict() {
        // This is what canonicality buys: the same document state produces the same bytes on
        // both platforms, so an edit applied twice is not mistaken for a divergence.
        #expect(Reconciler.decide(base: original, mine: localEdit, theirs: localEdit) == .inSync)
    }

    // MARK: - First sync (no base yet)

    @Test("Never synced, no server row → push (the insert path)")
    func insertsALocallyCreatedDocument() {
        #expect(Reconciler.decide(base: nil, mine: localEdit, theirs: nil) == .push)
    }

    @Test("Never synced, server row identical → in sync")
    func freshPullOfAnIdenticalRowIsNotAWrite() {
        #expect(Reconciler.decide(base: nil, mine: original, theirs: original) == .inSync)
    }

    @Test("Never synced and both sides hold different content at the same id → conflict")
    func divergentCreateIsAConflict() {
        #expect(Reconciler.decide(base: nil, mine: localEdit, theirs: remoteEdit)
                == .conflict(.divergentCreate))
    }

    @Test("Synced before, server row now gone → conflict, not a silent re-insert")
    func remoteDeletionIsSurfaced() {
        #expect(Reconciler.decide(base: original, mine: original, theirs: nil)
                == .conflict(.remoteDeleted))
    }

    // MARK: - Why byte comparison is legitimate here

    @Test("Every fixture reconciles as in-sync against its own canonical bytes")
    func canonicalBytesMakeEqualityAValidChangeTest() throws {
        for fixture in FixtureCorpus.all {
            let mirrored = try Delta.decode(json: fixture.canonicalBytes).canonicalJSON()
            #expect(
                Reconciler.decide(base: fixture.canonicalBytes, mine: mirrored, theirs: mirrored)
                    == .inSync,
                "\(fixture.name) would have produced a phantom write"
            )
        }
    }

    @Test("A whitespace-formatted server body is normalized before it reaches the reconciler")
    func jsonbNormalizationMustNotLookLikeAnEdit() throws {
        // Postgres jsonb does not return the bytes it was sent: it strips insignificant
        // whitespace and reorders object keys. This is what that response actually looks like
        // (captured from the live project), and it must not read as a remote edit.
        let asPostgresReturnsIt = Data(
            #"{"ops": [{"insert": "Hello", "attributes": {"bold": true}}, {"insert": "\n"}]}"#.utf8
        )
        let mine = Delta(ops: [.text("Hello", ["bold": .bool(true)]), .text("\n")]).canonicalJSON()

        #expect(asPostgresReturnsIt != mine, "the premise of this test would be void")

        let theirs = try Delta.decode(json: asPostgresReturnsIt).canonicalJSON()
        #expect(theirs == mine)
        #expect(Reconciler.decide(base: mine, mine: mine, theirs: theirs) == .inSync)
    }
}
