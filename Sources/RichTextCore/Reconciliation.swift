import Foundation

/// What sync should do with one document, given the three versions of it.
public enum SyncDecision: Equatable, Sendable {
    /// Local and remote already agree. No write, on either side.
    case inSync
    /// The local copy changed and the remote one did not. Push.
    case push
    /// The remote copy changed and the local one did not. Pull.
    case pull
    /// Base, local and remote all differ. Surfaced to the user, never resolved
    /// automatically — see `PRD.md`'s Non-Goals.
    case conflict(Conflict)

    public enum Conflict: Equatable, Sendable {
        /// Both sides edited since the last sync.
        case bothEdited
        /// The row is gone from the server but the local copy was synced from it once. The
        /// POC has no delete path, so this can only mean someone deleted the row out from
        /// under this client; it is surfaced rather than guessed at.
        case remoteDeleted
        /// Two rows with the same id appeared independently on both sides. Not reachable
        /// while ids are generated client-side and inserted with the row, but a wrong answer
        /// here would be silent content loss, so it is named rather than folded into `push`.
        case divergentCreate
    }
}

/// The three-way comparison the PRD's sync design rests on.
///
/// `lastSyncedDeltaJSON` is the **base**: the exact bytes this client last agreed with the
/// server on. With it, "these two differ" becomes answerable — *which side moved?* — instead
/// of a coin flip between clobbering the server and clobbering the user.
///
/// It compares **bytes, not documents**, and that is only sound because Delta is canonical:
/// exactly one byte sequence per document state (see `Delta.canonicalJSON`). Two callers that
/// encode the same document produce the same bytes, so equality is a valid "did anything
/// change" test and an unchanged document costs zero writes. Anything that broke canonicality
/// — a signed URL baked into an image op, an uncoalesced run, unsorted attribute keys — would
/// turn every comparison here into a phantom conflict, which is why those rules are enforced
/// upstream rather than papered over with a semantic diff here.
///
/// Note that server bytes must be **re-encoded through `Delta.canonicalJSON()` before they get
/// here.** Postgres `jsonb` does not preserve the bytes it was sent — it strips insignificant
/// whitespace, reorders object keys by (length, name), and re-escapes strings. A row pushed and
/// pulled straight back comes home with different bytes and identical content, so comparing the
/// raw response body against the local mirror reports a conflict on a document nobody touched.
public enum Reconciler {

    /// - Parameters:
    ///   - base: canonical bytes this client last synced, or `nil` if it never has.
    ///   - mine: canonical bytes of the local copy.
    ///   - theirs: canonical bytes of the server copy, or `nil` if the server has no such row.
    public static func decide(base: Data?, mine: Data, theirs: Data?) -> SyncDecision {
        guard let theirs else {
            // Never synced and no server row: this document was created locally. Insert it.
            return base == nil ? .push : .conflict(.remoteDeleted)
        }

        // Checked first so that base == mine == theirs, and the case where both sides
        // independently made the *same* edit, both land here as zero writes.
        if mine == theirs { return .inSync }

        guard let base else {
            // Both sides have a row at this id that this client never reconciled.
            return .conflict(.divergentCreate)
        }

        if base == theirs { return .push }   // only the local copy moved
        if base == mine { return .pull }     // only the server copy moved
        return .conflict(.bothEdited)        // both moved, differently
    }
}
