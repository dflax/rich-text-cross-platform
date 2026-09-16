# The storage contract

This project's client packages (`RichTextCore`, `RichTextEditor`, and the web editor once built)
don't talk to a database directly — they work in terms of a `Delta` value, an
`ImageFetching`/`RichTextImageUploading` protocol, and a three-way `SyncDecision`
(`RichTextCore/Reconciliation.swift`). Any backend that can satisfy the contract below works;
`backends/postgres/` is one real, worked implementation, not the only valid one.

## What a "document" row needs

| Concern | Requirement | Why |
|---|---|---|
| Content | A column holding the canonical `Delta` JSON (Quill's own format — `{"ops": [...]}`) | The single source of truth every client encodes to and decodes from. Never store derived HTML/plain-text as the primary copy. |
| Identity | A stable id, client- or server-generated | `RichTextCore` doesn't assume either; pick based on your sync design (client-generated ids make offline creation trivial, at the cost of needing to handle a divergent-create collision — see `Reconciliation.SyncDecision.Conflict.divergentCreate`). |
| Change detection | A monotonically increasing version (or a reliable `updated_at`) | `Reconciliation.decide(base:mine:theirs:)` needs to tell "changed since we last synced" from "didn't." An auto-incrementing integer/bigint is simpler to reason about than a timestamp (clock skew, same-millisecond writes); either works if it's reliable. |
| Concurrency | A write path that fails (not silently overwrites) when the caller's expected version is stale | This is what turns a lost-update race into a surfaced conflict instead of silent data loss. `backends/postgres/`'s `update_document` function is one way to do this; a transaction with `WHERE version = $expected` and checking the row count works equally well. |
| Images | Object keys only, never URLs, inside the `Delta` | A URL baked into the document changes the document's bytes the moment infrastructure changes (a new CDN, a bucket migration) — silently breaking the round-trip/canonicality guarantee and turning routine infra changes into phantom sync conflicts. `ImageStore`/`ImageFetching` resolve a key to a URL at *read* time, never before. |
| Denormalized search text (optional) | A plain-text column derived from `Delta`, maintained server-side | If you want to search or preview documents without decoding a `Delta` client-side, derive this once, in the database, on write — never let a client maintain it by hand, or it will drift. |

## What this project does *not* prescribe

- Whether ids are client- or server-generated.
- Real-time sync/push vs. poll-based sync.
- Auth model, multi-tenancy, row-level permissions — all backend/product concerns, not something
  a rich-text library should have an opinion about.
- Automatic conflict resolution. `Reconciliation` surfaces a conflict; deciding what a user sees
  and how they resolve it is your product's call.

## Why this looks like a Quill backend, because it is one

`Delta` here is not "Quill-inspired" or "Quill-compatible" — it's Quill's own `{"ops": [...]}`
format, unmodified, decoded and re-encoded byte-for-byte the same way on iOS, macOS, and the web
package (`web/packages/rich-text-editor` wraps Quill itself). If you already have a Quill
deployment — a plain `quill.js` editor, any Quill-based product, or a backend built against
[Quill's own documented Delta format](https://quilljs.com/docs/delta/) — the storage contract
above is not a new thing to design. It's the same contract, because it's the same document format:

- A "document" row that already stores Quill's Delta JSON already satisfies the Content row above.
  Nothing about adding this project's native iOS/macOS editors requires a migration, a new column,
  or a transform step — the same row a `quill.js` frontend reads and writes today is what
  `NSDeltaCodec` decodes on the client side.
- The version/concurrency and image-key requirements above aren't new constraints this project is
  imposing — they're the same considerations any multi-writer Quill deployment already has to
  solve (or has already solved) once more than one client can edit the same document. This project
  just writes them down explicitly and gives the native side (`Reconciliation.decide`) an actual
  implementation to plug into.
- The one place native and web genuinely diverge is *rendering* the vocabulary a document is
  allowed to contain — `Vocabulary.swift` (Swift) and `vocabulary.ts` (web) both enforce the same
  allowed-ops list, checked against the same fixture corpus (`fixtures/`) in both languages' test
  suites, specifically so a document one platform considers valid can't be silently rejected or
  mis-rendered by the other.

In short: adding a native editor on top of an existing Quill/web product is additive, not a
parallel format to keep in sync by hand. The web package is a thinner wrapper around Quill itself,
not a reimplementation, so "does this work with our existing Quill setup" is closer to "yes,
already" than "here's the migration plan."

## Per-backend guidance

- [`backends/postgres/`](../../backends/postgres/) — a real, working schema + migration.
- [`mysql.md`](mysql.md), [`mongodb.md`](mongodb.md), [`firebase.md`](firebase.md),
  [`cloudkit.md`](cloudkit.md), [`supabase.md`](supabase.md) — guidance mapping the same contract
  onto each store. CloudKit is the structurally different one — no server your app talks to, and
  a real private/shared/public database decision none of the others force on you. Supabase is
  "just Postgres" underneath, but the fork point this project came from actually ran on it — its
  guide carries a real, non-obvious lesson about optimistic concurrency under row-level security
  that only showed up by building it.
- [`powersync.md`](powersync.md) — a different kind of guide: an offline-first sync engine that
  sits *downstream of* a primary database (pairing with `backends/postgres/` or `supabase.md`)
  rather than being one itself. Covers a real, verified integration with PowerSync's Swift SDK,
  including where this project's own `Reconciliation` plugs into its write-back path.
- [`CATALOG.md`](CATALOG.md) — the fuller provider landscape: every distinct storage technology
  or provider worth considering (managed Postgres/MySQL flavors, other document stores, other
  Apple-native options, bundled backend-as-a-service platforms, GraphQL layers, and other
  offline-first sync engines), not just the seven above with a written guide today.
