# Backend provider catalog

`docs/backends/README.md` defines the storage **contract** this project actually depends on: a
`Delta` JSON column, a version/updated-at pair for optimistic concurrency, and an object-key
image reference resolved to a URL only at read time. Anything that can satisfy that contract
works. This file is the fuller landscape of *what* could satisfy it — every distinct storage
technology or provider worth naming, not just the five with a written guide today
(`postgres/`, `mysql.md`, `mongodb.md`, `firebase.md`, `cloudkit.md`) — so a host app's team can
pick deliberately rather than defaulting to whatever's most familiar without seeing the
alternatives.

Nothing here is a recommendation of one provider over another — this project has no opinion on
that (see `docs/backends/README.md`'s "What this project does not prescribe"). Entries are
grouped by storage shape, with a one-line note on what's actually distinctive about each for
*this* contract specifically (a JSON blob, optimistic concurrency, object-key images) — not a
general feature comparison. **Status column**: some things listed here are stable, some are
younger companies/products — verify current status before depending on one, especially for
anything marked with a caveat.

## Already have a written guide

| Provider/technology | Guide | Notes |
|---|---|---|
| PostgreSQL (generic) | [`../../backends/postgres/`](../../backends/postgres/) | Real, working schema + migration — the most complete guidance in this repo. |
| MySQL / MariaDB | [`mysql.md`](mysql.md) | |
| MongoDB (generic + Atlas) | [`mongodb.md`](mongodb.md) | |
| Firebase (Firestore + Storage) | [`firebase.md`](firebase.md) | Covers Firestore specifically, not Realtime Database — see below. |
| CloudKit | [`cloudkit.md`](cloudkit.md) | Structurally different from every other entry here — no server your app talks to, and `CKError.serverRecordChanged` hands back exactly the three records `Reconciliation.decide(base:mine:theirs:)` needs, unprompted. |

## Relational / SQL — managed and serverless flavors of Postgres/MySQL

All of these speak the Postgres or MySQL wire protocol, so `postgres/`'s schema and
`update_document()` function (or `mysql.md`'s guidance) applies close to unchanged — the
differences that matter for this contract are around concurrency limits, cold starts, and how
`gen_random_uuid()`/optimistic-locking triggers are enabled, not the schema shape itself.

- **Supabase** — Postgres, plus bundled auth/storage/realtime. Already gets a section in
  `backends/postgres/README.md` ("just Postgres," runs the same migration unchanged) since it's
  the fork point's own original backend; doesn't have a *dedicated* guide file yet because there's
  little to add beyond "run `backends/postgres/migrations/001_documents.sql`." A dedicated
  `supabase.md` would mainly be worth writing to cover Supabase Storage specifically as the
  `ImageFetching`/`RichTextImageUploading` target (parallel to `firebase.md`'s Storage section) —
  see "Not yet written, worth writing" below.
- **Neon** — serverless Postgres with instant branching (a full copy-on-write branch per PR/
  environment). The interesting property for this contract: branching gives you a free, real
  Postgres copy for testing the `update_document()` concurrency function against concurrent
  writes without touching a shared database.
- **Amazon Aurora (Postgres/MySQL-compatible) / RDS** — the "just provision a managed instance"
  AWS path. Same schema, standard AWS IAM/VPC concerns layered on top; nothing contract-specific.
- **Google Cloud SQL (Postgres/MySQL) / AlloyDB** — same story on GCP; AlloyCB adds
  Postgres-compatible horizontal read scaling if a document table gets large enough to need it.
- **Azure Database for PostgreSQL / MySQL** — same story on Azure.
- **CockroachDB** — distributed SQL, Postgres wire-compatible, so `postgres/`'s schema applies,
  but `update_document()`'s single-row optimistic-concurrency pattern is exactly the shape
  CockroachDB's distributed transactions handle well — worth considering if documents need to
  survive a regional outage, not just a single-instance failure.
- **PlanetScale** — serverless MySQL (Vitess-based), branching similar to Neon. PlanetScale's own
  branching + non-blocking schema change workflow is a real advantage if `documents`' schema
  itself is expected to evolve (e.g. adding a new denormalized column later).
- **Turso / libSQL** — SQLite, distributed to the edge (many read replicas close to users).
  Notable specifically for this contract because SQLite has no native `jsonb` type — store
  `delta` as a `text` column holding the canonical JSON string directly, which sidesteps the exact
  "the database reorders JSON keys on the way in" trap `PROVENANCE.md`/`docs/ARCHITECTURE.md`
  document Postgres `jsonb` having (a plain `text` column is byte-for-byte, by construction).
- **Cloudflare D1** — SQLite at the edge via Cloudflare Workers. Same `text`-column note as Turso
  applies. Interesting if the rest of a host app's backend already lives on Workers.
- **Xata** — serverless Postgres with built-in full-text search on top. The search index would be
  a natural home for the storage contract's "denormalized plain-text column" row, without needing
  a separate search service.

## Document / NoSQL

- **Firebase Realtime Database** — distinct from Firestore (which `firebase.md` covers), and
  older/simpler: one big JSON tree rather than a document/collection model. Storing a `Delta`
  under `documents/{id}/delta` works, but RTDB's shallow-merge-on-write semantics make the
  optimistic-concurrency check (`update_document`'s "stale version matches zero rows" pattern)
  harder to express atomically than Firestore's real transactions — worth a dedicated note if this
  ever gets picked over Firestore specifically, since the two are easy to conflate as "Firebase."
- **Google Cloud Firestore (accessed as a standalone GCP service, not via the Firebase SDK)** —
  the identical underlying database `firebase.md` already documents; only the client library and
  IAM model differ. `firebase.md`'s guidance applies unchanged.
- **Amazon DynamoDB** — key-value/wide-column, not really "document" in the MongoDB sense, but
  commonly reached for on AWS. Storing `delta` as a DynamoDB `Map` attribute (or a `String`
  holding the JSON, for the same byte-fidelity reason as the SQLite note above) both work; the
  version/optimistic-concurrency row of the contract maps directly onto DynamoDB's native
  conditional writes (`ConditionExpression: "version = :expected"`) — arguably a *more* natural
  fit for this contract's exact optimistic-locking shape than a hand-rolled SQL trigger.
- **Azure Cosmos DB** — multi-model (its "Core (SQL) API" is the common choice), with native
  optimistic concurrency via ETags — another natural fit for this contract's version-check
  pattern, using Cosmos's own ETag rather than a bespoke `version` column.
- **Couchbase / Couchbase Lite** — worth calling out specifically for its *sync* story:
  Couchbase Lite is an embedded, on-device database with a Sync Gateway (or Capella App Services,
  the managed version) that handles exactly the kind of offline-first, eventually-consistent sync
  `RichTextCore.Reconciliation` is designed to sit downstream of. A host already committed to
  Couchbase's replication model would likely want Reconciliation's three-way `SyncDecision` to
  inform *when* to trigger a manual conflict-resolution UI on top of Couchbase's own automatic
  replication, not replace it.
- ~~**FaunaDB**~~ — Fauna's commercial service wound down; do not build against it for anything
  new. Left here only so its absence doesn't look like an oversight. Verify current status before
  considering any managed document database not listed here that hasn't been checked recently —
  this space moves fast.

## Apple-native (no separate backend service to run)

- **CloudKit** — see [`cloudkit.md`](cloudkit.md), now written up in full: a `CKRecord` per
  document, syncing across a user's own devices with zero backend infrastructure to operate, and
  a native conflict-handling mechanism (`CKError.serverRecordChanged`) that maps onto
  `Reconciliation.SyncDecision` more directly than any REST backend in this catalog — the error
  hands back the server's current record, the client's attempted record, *and* the common
  ancestor when available, which is the exact three-way shape `Reconciliation.decide(base:mine:
  theirs:)` already expects, with no extra round-trip needed to fetch any of them. The real
  decision the guide covers in full: private (single-user, automatic), shared (`CKShare`, genuine
  multi-user), or public (visible to every user of your app) database — a choice CloudKit forces
  explicitly where a REST backend lets you defer it.
- **SwiftData + CloudKit sync** — Apple's higher-level persistence framework, with automatic
  CloudKit sync as an opt-in. Worth noting as distinct from raw CloudKit above: SwiftData's own
  sync is automatic and mostly invisible, which is convenient but gives a host app *less* direct
  control over the exact moment a conflict is detected — likely a worse fit than raw CloudKit for
  a library whose whole sync story (`Reconciliation`) assumes the host is driving reconciliation
  deliberately.

## Backend-as-a-service platforms (bundled auth + database + storage + functions)

Several of these are already listed above by their underlying database (Firebase → Firestore,
Supabase → Postgres) since the database is what this contract actually touches; listed again here
as a group because "which BaaS platform" is often the real decision a team is making, with the
underlying database as a secondary detail.

- **Firebase**, **Supabase** — see above.
- **Appwrite** — self-hostable, Postgres-backed as of its newer versions (MariaDB in older ones —
  verify which your deployment runs). Appwrite's own Storage service covers the image side of the
  contract directly.
- **PocketBase** — a single self-contained binary, SQLite-backed, with a built-in admin UI and
  realtime subscriptions. Notable for how little there is to operate — a real option for a small
  or early-stage host app that wants "a backend" without provisioning separate infrastructure.
  The SQLite-as-`text`-column note above applies.
- **Backendless** — bundled BaaS with a visual data-modeling UI; standard document-store shape
  underneath.
- **Parse Server** — open-source, self-hostable (the platform Backendless/Firebase-style products
  are often compared against); runs on MongoDB or Postgres depending on version/configuration, so
  it inherits whichever of those two sections above actually applies to a given deployment.
- **Nhost** — Postgres + Hasura (GraphQL) + auth + storage, bundled. The Postgres schema in
  `backends/postgres/` applies directly underneath; Hasura's auto-generated GraphQL API becomes
  the client's actual read/write surface instead of raw SQL.
- **AWS Amplify (DataStore + AppSync + Cognito)** — AWS's own bundled offering. AppSync's
  conflict-resolution modes (including a "custom Lambda resolver" mode) are the natural place to
  encode the same optimistic-concurrency check `update_document()` expresses in SQL.
- **Convex** — a reactive backend-as-a-service with its own document database and
  server-side TypeScript functions, not built on top of Postgres/Mongo. Its transactions and
  optimistic-concurrency primitives are a reasonable fit for this contract; a real integration
  would look more like a from-scratch adapter than "point `ImageFetching` at a URL," since
  Convex's data access pattern (reactive queries via generated client code) is more opinionated
  than a REST/SQL backend.

## GraphQL as the access layer (not a storage engine itself)

These sit *in front of* one of the databases above — listed separately because "GraphQL vs. REST
vs. raw SQL" is a real integration decision independent of which database is actually storing the
`Delta`.

- **Hasura** — auto-generates a GraphQL (and REST) API directly over Postgres; used standalone or
  as Nhost's underlying engine (see above). The `documents` table from `backends/postgres/` is
  exposed with close to zero extra configuration; `update_document()` becomes a Hasura Action or
  a Postgres function exposed as a GraphQL mutation.
- **AWS AppSync** — see Amplify above; also usable standalone in front of DynamoDB, Aurora, or a
  Lambda resolver calling anything else.

## Sync/offline-first engines (sit downstream of a primary database)

Distinct from a database itself: these products exist specifically to keep a local, on-device
copy in sync with a server copy, which is exactly the problem `RichTextCore.Reconciliation`'s
three-way comparison is designed to sit alongside — most relevant to a host app that wants
real offline editing, not just offline *reading* (`ImageStore` already covers offline image reads
regardless of which of these, if any, is used for the document data itself).

- **PowerSync** — a sync engine that layers real-time, offline-first sync on top of an existing
  Postgres or MySQL database (including Supabase) without requiring a schema rewrite. Likely the
  most natural fit for a host already using `backends/postgres/`'s schema who wants offline
  editing without adopting a different primary database.
- **ElectricSQL** — a similar local-first Postgres sync engine, with an embedded SQLite (or
  PGlite) client-side store that stays live-synced with a Postgres server.
- **Realm / Atlas Device Sync** (MongoDB-owned) — an embedded object database with a managed sync
  service; the natural pairing for a host already on MongoDB Atlas (see `mongodb.md`) that wants
  the sync engine to handle conflict resolution rather than driving `Reconciliation` manually.
- **Couchbase Lite + Sync Gateway / Capella App Services** — see the Couchbase entry above.

## The generic fallback, always available

Nothing on this list is required — `docs/backends/README.md`'s contract is deliberately
implementation-agnostic. Any backend reachable over HTTP(S) that can store a JSON blob, enforce
an optimistic-concurrency check, and serve image bytes from an object key satisfies it, via a
plain `ImageFetching`/`RichTextImageUploading` conformance and whatever read/write client code
talks to it — a REST API, a GraphQL endpoint, even a gRPC service. `PublicURLImageFetcher` already
covers "plain HTTPS GET from a public bucket/CDN," which is the read side of most of the storage
options above (S3-compatible object storage in particular — R2, Backblaze B2, DigitalOcean
Spaces, MinIO self-hosted — is its own axis, orthogonal to which database stores `delta` itself,
and already covered generically by that one fetcher).

## Not yet written, worth writing (tracked in `docs/ROADMAP.md`)

CloudKit was the most differentiated gap on this list for an Apple-focused package — written up
in full as [`cloudkit.md`](cloudkit.md) on 2026-09-15, verified by direct compilation against the
real CloudKit SDK rather than written from documentation alone. Remaining, ordered by how much a
dedicated doc would actually add beyond this catalog entry:

1. **Supabase Storage** (as the `ImageFetching`/`RichTextImageUploading` target specifically) —
   the database side is already covered by "just Postgres"; only the image-storage side is a real
   gap, parallel to `firebase.md`'s own Storage section.
2. **PowerSync or ElectricSQL**, whichever a host is more likely to reach for first — worth one
   concrete worked example of pairing an offline-first sync engine with this project's own
   `Reconciliation`, since that combination is genuinely different from "just point `ImageFetching`
   at a REST endpoint" and the existing four guides don't touch it at all.
