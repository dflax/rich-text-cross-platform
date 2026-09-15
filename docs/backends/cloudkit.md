# CloudKit

Guidance, not shipped code — see [`README.md`](README.md) for why this project doesn't ship an
adapter per store. Mapping the [storage contract](README.md) onto CloudKit — verified against the
real CloudKit SDK (`import CloudKit`, typechecked directly), not written from documentation alone.

CloudKit is a structurally different fit than every other backend in this catalog: there's no
server your app talks to over a REST/SQL API you control. A `CKRecord` syncs to iCloud through
Apple's own client SDK, and — the one decision every other guide here doesn't have to make —
*which* CloudKit database a document lives in changes who can read and write it at all. Read the
"Private, shared, or public" section before the rest of this guide; it changes what "a document"
even means here.

## Record shape

```
recordType: "Document"
recordID:   CKRecord.ID(recordName: <your document id>, zoneID: <a custom zone — see below>)

title:      String
delta:      String     // canonical Delta JSON — see note below
plainText:  String
version:    Int64       // optional — see "Change detection" below, CloudKit has its own
```

**`delta` as a `String`, not a nested structure.** Unlike Firestore or MongoDB, `CKRecord` fields
are typed scalars/blobs (`String`, `Data`, `Int64`, `CKAsset`, …) with no native "arbitrary JSON
object" field type — there's nothing to map `Delta`'s `ops` array onto the way Firestore's
array-of-maps is a natural fit. Store the canonical JSON string byte-for-byte instead, which is
actually the *safer* choice for this project's own guarantees: nothing about a `CKRecord` field
can silently reorder object keys or reformat whitespace the way Postgres's `jsonb` column does
(see `docs/ARCHITECTURE.md`/`PROVENANCE.md` for why that specific failure mode mattered enough to
be a named finding elsewhere in this project) — a `String` field is exactly the bytes you put in.

**Record size.** CloudKit caps total record size (roughly 1MB as of recent SDKs — check current
limits before relying on the exact number). An extremely long document could approach that on the
text alone; this is a real, CloudKit-specific ceiling none of the SQL/NoSQL guides in this catalog
have to think about. `CKAsset` (see "Images" below) exists precisely to keep large blobs out of
the record's own size accounting.

## Identity

`CKRecord.ID(recordName:zoneID:)` accepts a custom string — use your own client-generated id
directly as `recordName` rather than introducing a second identifier. Put documents in a **custom
zone**, not the default zone: only a custom zone supports atomic multi-record batch saves and
(for the private database) the change-token-based sync CloudKit's own incremental-fetch APIs
depend on. `CKRecordZone.ID(zoneName:ownerName:)`, with `ownerName: CKCurrentUserDefaultName` for
the private database.

## Change detection & optimistic concurrency — CloudKit's best fit in this whole catalog

This is the one place CloudKit is a *better* match for `RichTextCore.Reconciliation` than a
typical REST backend, not just an equally-valid one. Every `CKRecord` carries a
`recordChangeTag: String?` that CloudKit manages internally — you never set it, and saving a
record whose change tag doesn't match the server's current one fails outright, with the full
context needed to reconcile handed back to you in the error itself:

```swift
do {
    let saved = try await database.save(record)
    // saved.recordChangeTag is the new tag — nothing else to track.
} catch let error as CKError where error.code == .serverRecordChanged {
    let theirs = error.serverRecord   // the record actually on the server right now
    let mine = error.clientRecord     // what you tried to save
    let base = error.ancestorRecord   // the common ancestor, when CloudKit can determine one
    // Encode each record's `delta` field through Delta.canonicalJSON() (they're already the
    // canonical bytes if this project's own encoder produced them, but never assume — a record
    // read back from CloudKit is exactly what "theirs" should be compared as) and feed the three
    // to Reconciliation.decide(base:mine:theirs:) directly. No extra round-trip to fetch "theirs"
    // separately, unlike a REST backend where a 409 typically only tells you "it changed," not
    // what it changed to.
}
```

No separate `version` column is required — `recordChangeTag` already *is* the change-detection
and concurrency-control token in one, opaque and CloudKit-managed rather than an integer your
own write path increments. Keep an app-level `version` field anyway only if your own UI wants a
human-readable "revision 4" to display; it plays no role in the concurrency check above.

## Derived plain text

No generated-field equivalent, the same as every other non-relational store in this catalog —
compute `plainText` client-side (walk `delta`'s ops, concatenate every string `insert`) in the
same write that sets `delta`. CloudKit has no server-side compute story (no Cloud Functions
equivalent) short of a separate server process watching CloudKit's own change notifications, which
is real infrastructure to run for a field this cheap to compute inline.

## Images

Two real options, and they trade off differently than every other backend here:

- **Keep this project's existing object-key pattern.** Store images in any plain object store
  (S3-compatible, or even a CloudKit **public** database's `CKAsset` field acting as nothing more
  than "a blob CloudKit happens to host"), and put the key in the `Delta`'s image op exactly as
  every other backend guide describes — `PublicURLImageFetcher` or a custom `ImageFetching`
  conformance, unchanged.
- **`CKAsset` on the document's own private-database record.** CloudKit stores `CKAsset` values as
  files outside the record's own size accounting, downloaded on demand — a real fit if you want
  images to travel with the document through the *same* private-iCloud sync this guide's identity/
  concurrency sections describe, with no separate object-storage account to provision at all. The
  cost: `CKAsset` values resolve to a local file URL through CloudKit's own download machinery, not
  a plain HTTPS GET, so `ImageFetching`'s "resolve a key to a URL" shape needs a CloudKit-specific
  conformance rather than `PublicURLImageFetcher` — and this only works at all inside the private
  or shared database (see below); a public database's assets are still fetched through CloudKit's
  API, not a bare URL, so even there `PublicURLImageFetcher` doesn't directly apply.

## Private, shared, or public — the decision every other guide here skips

Every SQL/NoSQL backend in this catalog assumes a multi-tenant server your app's users all talk
to, with authorization as a layer you build on top. CloudKit's three databases
(`CKContainer.privateCloudDatabase` / `.sharedCloudDatabase` / `.publicCloudDatabase`) are a
different shape entirely, and picking one is a real product decision this project has no opinion
on (per `README.md`'s "What this project does not prescribe" — CloudKit just makes the decision
unusually explicit and unavoidable, where a REST backend lets you defer it):

- **Private database** — scoped to one user's own iCloud account, invisible to anyone else,
  including you (Apple cannot read it either). The natural fit for personal notes/documents with
  no collaboration story at all. Sync across a user's own devices is free and automatic; there is
  no "other user" to reconcile against, so `Reconciliation` only ever resolves *this device* vs.
  *this same user's other device*, never a genuine multi-user conflict.
- **Shared database** — a private-database record explicitly shared with specific other iCloud
  users via `CKShare`, the actual multi-user collaboration path. This is where
  `Reconciliation.SyncDecision.conflict(.bothEdited)` becomes a real, expected case rather than an
  edge case — two genuine people editing the same document.
- **Public database** — visible to every user of your app, read/write permissions your own
  responsibility to enforce (CloudKit's public database has coarse read/write-all-or-nothing
  semantics per record type by default; per-record access control needs your own design on top).
  Rarely the right fit for a personal document editor; more plausible for something like a shared
  template library.

Getting this wrong isn't a schema mistake to fix later — private, shared, and public are separate
CloudKit databases with separate record graphs, so migrating a document from one to another later
is a real data-migration project, not a config change.

## What CloudKit does not give you that the SQL/NoSQL guides in this catalog do

No arbitrary server-side query language, no full-text search across `plainText` without exporting
to a separate index (CloudKit query expressiveness is deliberately limited), and no equivalent of
a database trigger. If your product needs any of those, CloudKit is likely a component of your
storage story rather than the whole of it — some teams use CloudKit for the sync/offline story
specifically and a conventional backend for search/analytics, accepting the two-systems cost for
what each is actually good at.
