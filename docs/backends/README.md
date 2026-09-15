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

## Per-backend guidance

- [`backends/postgres/`](../../backends/postgres/) — a real, working schema + migration.
- [`mysql.md`](mysql.md), [`mongodb.md`](mongodb.md), [`firebase.md`](firebase.md),
  [`cloudkit.md`](cloudkit.md), [`supabase.md`](supabase.md) — guidance mapping the same contract
  onto each store. CloudKit is the structurally different one — no server your app talks to, and
  a real private/shared/public database decision none of the others force on you. Supabase is
  "just Postgres" underneath, but the fork point this project came from actually ran on it — its
  guide carries a real, non-obvious lesson about optimistic concurrency under row-level security
  that only showed up by building it.
- [`powersync-electric.md`](powersync-electric.md) — a different kind of guide: offline-first sync
  engines that sit *downstream of* a primary database (pairing with `backends/postgres/` or
  `supabase.md`) rather than being one themselves. Covers a real, verified integration with
  PowerSync's Swift SDK, and why Electric (formerly ElectricSQL) currently isn't a fit for the
  Swift editor specifically.
- [`CATALOG.md`](CATALOG.md) — the fuller provider landscape: every distinct storage technology
  or provider worth considering (managed Postgres/MySQL flavors, other document stores, other
  Apple-native options, bundled backend-as-a-service platforms, GraphQL layers, and other
  offline-first sync engines), not just the six above with a written guide today.
