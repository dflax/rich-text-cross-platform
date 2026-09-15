# Offline-first sync engines: PowerSync and Electric

Guidance, not shipped code — see [`README.md`](README.md) for why this project doesn't ship an
adapter per store. These two are a different *kind* of entry than every other guide in this
catalog: neither is a primary database. Both sit **downstream of** one (Postgres, in both cases
here — pairing naturally with `backends/postgres/` or [`supabase.md`](supabase.md)), keeping a
reactive, queryable local copy in sync with it. That's a genuinely different integration shape
than "point `ImageFetching` at a REST endpoint," which is why this gets its own guide rather than
a `CATALOG.md` entry.

Researched directly against each project's current documentation and, for PowerSync, its real
Swift SDK — verified by resolving the actual SPM package and reading its shipped source and demo
code, not written from memory or documentation alone. Both products move fast; verify the
specifics below (especially client support) before depending on them.

**The headline finding, upfront: these two are not interchangeable for this project.** PowerSync
has a real, working Swift SDK. Electric (the current name for what was ElectricSQL) does not, as
of this writing — its client libraries are TypeScript, React, and Elixir only. For a Swift-first
editor, that asymmetry decides most of the practical question before the architecture comparison
even starts.

## PowerSync

### Architecture

PowerSync syncs a Postgres (or MongoDB/MySQL/SQL Server) backend to an **embedded SQLite database
on the client**, through a hosted or self-hosted "PowerSync Service" that consumes your database's
change stream. Two directions, genuinely different mechanisms:

- **Read path**: the PowerSync Service watches your backend's changes and streams matching rows
  down into the client's local SQLite tables, driven by "sync rules" you define server-side
  (which rows a given client should receive).
- **Write path**: your app writes directly to the **local** SQLite database first — instant,
  offline-capable, no network round-trip on the critical path. The SDK queues those local writes
  into a CRUD upload queue automatically. You implement one function,
  `uploadData(database:)`, that drains the queue and applies each entry to your actual backend
  however you see fit.

That write-path design is exactly why this pairs well with `Reconciliation`: PowerSync's own
default conflict behavior is last-write-wins, and it explicitly expects *you* to build real merge/
conflict logic server-side if you need it — it doesn't pretend to solve that for you. That's the
same posture this project's own `Reconciliation.decide(base:mine:theirs:)` takes (surface a
conflict, never resolve one silently), so the two compose rather than duplicate or fight each
other.

### The Swift SDK — real, verified

```swift
.package(url: "https://github.com/powersync-ja/powersync-swift", from: "1.0.0")
```

Resolves and builds cleanly (confirmed directly) with a `PowerSync` product, minimum iOS 15 /
macOS 12 — well below this project's own iOS 26 / macOS 26 floor, so no conflict adding it
alongside `RichTextCore`/`RichTextEditor`.

```swift
import PowerSync

let db = PowerSyncDatabase(
    schema: Schema(tables: [
        Table(name: "documents", columns: [
            .text("title"),
            .text("delta"),       // canonical Delta JSON, stored as a plain string — see below
            .text("plain_text"),
            .integer("version"),
        ]),
    ])
)

try await db.connect(connector: SupabaseConnector(supabase: supabase), options: nil)

// Reactive read: fires every time the local copy changes, from either direction.
for try await rows in try db.watch(
    "SELECT * FROM documents WHERE id = ?",
    parameters: [documentID],
    mapper: { cursor in try cursor.getString(index: 1) }  // decode through Delta.decode(json:)
) { /* update UI */ }

// Local write — instant, queued for upload automatically.
try await db.execute(
    sql: "UPDATE documents SET delta = ?, version = version WHERE id = ?",
    parameters: [encodedCanonicalDelta, documentID]
)
```

**`delta` as a plain `text` column, not a nested structure** — SQLite has no native JSON object
type any more than the SQLite-backed edge databases in `CATALOG.md` do. Store the canonical JSON
string byte-for-byte, the same choice `cloudkit.md` makes and for the same reason: nothing about a
`text` column can reorder keys or reformat whitespace the way a `jsonb` column on the Postgres side
already does (see `docs/ARCHITECTURE.md`/`PROVENANCE.md` for why that specific failure mode was
worth naming elsewhere in this project).

### The write-back connector — where `Reconciliation` actually plugs in

PowerSync's own official Supabase demo (`Demos/GRDBDemo` in the `powersync-swift` repo) shows the
shape directly — read straight from the SDK's own shipped source, not paraphrased:

```swift
final class SupabaseConnector: PowerSyncBackendConnectorProtocol {
    func fetchCredentials() async throws -> PowerSyncCredentials? {
        guard let session = supabase.session else { return nil }
        return PowerSyncCredentials(endpoint: powerSyncEndpoint, token: session.accessToken)
    }

    func uploadData(database: PowerSyncDatabaseProtocol) async throws {
        guard let transaction = try await database.getNextCrudTransaction() else { return }
        for entry in transaction.crud {
            switch entry.op {
            case .put:   try await supabase.client.from(entry.table).upsert(entry.opData ?? [:]).execute()
            case .patch: try await supabase.client.from(entry.table).update(entry.opData ?? [:]).eq("id", value: entry.id).execute()
            case .delete: try await supabase.client.from(entry.table).delete().eq("id", value: entry.id).execute()
            }
        }
        try await transaction.complete()
    }
}
```

The stock demo's `.patch` case does a plain `.update(...)` — last-write-wins, no version check.
**To route through this project's own optimistic concurrency instead**, special-case the
`documents` table in that same `switch` and call the `update_document()` RPC
(`backends/postgres/`/`supabase.md`) with the local row's own `version` as `p_expected_version`,
rather than a bare `.update`:

```swift
case .patch where entry.table == "documents":
    let expectedVersion = entry.opData?["version"] as? Int ?? 0
    let rows = try await supabase.client.rpc("update_document", params: [
        "p_id": entry.id, "p_expected_version": expectedVersion, /* … */
    ]).execute().value as [RemoteDocumentRow]
    guard let updated = rows.first else {
        // Empty result: the same disambiguation supabase.md's optimistic-concurrency
        // section describes — re-read and feed (base, mine, theirs) to Reconciliation
        // rather than assuming staleness.
        return
    }
```

This is real, non-trivial integration work — PowerSync's CRUD queue gives you *an* op to apply,
not a conflict-aware write by default — but it's exactly the kind of place this project's own
`Reconciliation` was designed to slot into rather than be redundant with.

## Electric (formerly ElectricSQL)

### What it actually is now — a real pivot, not a rename

Electric markets itself today as **"a read-path sync engine for Postgres"** — that phrasing is
load-bearing, not marketing color. It syncs data **out of** Postgres to clients efficiently
(partial replication via a "Shape" — a table subset defined by a `WHERE` clause — streamed over
plain HTTP, backed by Postgres logical replication), and is explicit that **writes go back through
your own API**, documented under its own "Writes" guide as "patterns for writing data back through
your API" rather than as a built-in bidirectional sync path. This is a genuine architectural
choice, not a missing feature — Electric is solving "efficient fan-out reads to many concurrent
clients" as its core problem, not "make writes offline-capable," and says so.

**No Swift client.** Electric's client libraries are TypeScript, React, and Elixir. There is
nothing here for the native Swift editor this project ships — this isn't a gap to work around
today, it's a real, current limit worth re-checking before it changes anyone's plans, given how
fast this specific space moves (Electric itself is mid-rebrand from "ElectricSQL" as of this
writing).

### Where it could still fit this project

Not the Swift editor — the **web package** (`web/packages/rich-text-editor`, Quill-based,
genuinely web/TypeScript). A web-based collaborative reading/editing surface with many concurrent
viewers of the same document is exactly Electric's stated strength (efficient fan-out to many
clients), and its client is a real fit for that package specifically, unlike the Swift side. Writes
would still go through a conventional API endpoint calling `update_document()` directly — Electric
wouldn't replace that path, only make the read side (watching a document update live as other
users edit it) cheaper to build than hand-rolled polling or a bespoke WebSocket layer.

### Recommendation given this project's shape

**PowerSync, if you want offline-first sync for the Swift editor at all** — it has the Swift SDK,
a real official Supabase integration to build from, and a write-path hook that composes with
`Reconciliation` rather than competing with it. **Electric, only for the web package's read side,
and only revisit for the Swift side if/when it ships a native client** — check its current client
list before assuming that hasn't changed, since this whole space (including Electric's own
naming) has moved meaningfully even within this project's own lifetime.
