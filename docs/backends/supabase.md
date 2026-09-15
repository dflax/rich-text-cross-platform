# Supabase

Guidance, not shipped code — see [`README.md`](README.md) for why this project doesn't ship an
adapter per store. Supabase's database *is* Postgres, so
[`backends/postgres/`](../../backends/postgres/)'s schema and `update_document()` function apply
close to unchanged; this guide is the Supabase-specific layer on top (auth, RLS, and the one
genuinely non-obvious lesson below) plus Supabase Storage for images.

This isn't written from documentation alone — the fork point this project was extracted from (see
`PROVENANCE.md`) ran on Supabase for real, and the lessons below (particularly the
optimistic-concurrency disambiguation one) came from building and hitting them, not from reading
Supabase's docs. It did **not** use Supabase Storage for images — it used a plain S3-compatible
bucket instead, wired through exactly the `ImageFetching`/`RichTextImageUploading` pattern this
project already documents. The Storage section below is real, verified Supabase API (confirmed
via current documentation, not assumed), but — unlike the database/auth sections — it wasn't the
fork point's own path, and says so at each point that matters.

## Database: apply `backends/postgres/`'s schema, then layer on RLS

Supabase adds nothing to the table shape itself — `id`, `title`, `body`/`delta` as `jsonb`,
`plain_text`, `updated_at`, `version` are unchanged. What Supabase adds is `auth.users` and row
level security, which turn "who may read/write this row" from an application-layer concern into a
database-enforced one:

```sql
alter table documents enable row level security;

create policy documents_select_authenticated
  on documents for select
  to authenticated
  using (true);

create policy documents_write_admin
  on documents for all
  to authenticated
  using (is_admin())
  with check (is_admin());
```

**Modeling an admin/writer role without a separate table.** A `profiles`/`user_roles` table is the
obvious instinct, but costs a table, its own RLS policies, and (if that table's own policies
reference `documents`, or vice versa) a real risk of RLS policy recursion. The fork point's own
answer: a claim in `auth.users.raw_app_meta_data` (`{"role": "admin"}`), which Supabase's auth
server copies into every access token's `app_metadata` claim automatically —

```sql
create or replace function is_admin()
returns boolean
language sql
stable
as $$
  select coalesce(auth.jwt() #>> '{app_metadata,role}', '') = 'admin';
$$;
```

`app_metadata` (unlike `user_metadata`) is writable only through the Supabase admin API — a
service-role key, never a user's own session — so a signed-in user cannot grant themselves admin
by editing their own profile. That's the actual security property this pattern buys: no extra
table, no extra policies to keep consistent, no `security definer` helper needed to dodge
self-referential RLS.

## Optimistic concurrency — and the one thing that isn't obvious until you build it

The write path is `backends/postgres/`'s `update_document()` RPC, called through
Supabase's PostgREST layer (`/rest/v1/rpc/update_document`) or the official SDK's
`.rpc(...)` call — identical function, identical "stale version returns an empty result" contract.

**The real trap: an empty result is ambiguous under RLS, in a way it isn't on plain Postgres.**
`backends/postgres/`'s own contract says a stale `expected_version` returns zero rows. Under
Supabase's RLS, a write **blocked by policy** *also* returns zero rows — the `UPDATE`'s `USING`
clause filters it out before it can even be attempted, and PostgREST cannot tell you "policy
blocked this" apart from "nothing matched." A reader with no write access and a stale-version
writer look identical from the empty array alone. The fork point's own fix, worth carrying into
any Supabase integration: **when the RPC returns nothing, re-read the row and compare its current
version against what you expected**:

```swift
let rows = try await rpc("update_document", params: [...])
if let row = rows.first { return .updated(row) }

// Empty response. Disambiguate by re-reading — don't guess.
guard let current = try await fetchDocument(id: documentID) else { return .vanished }
return current.version == expectedVersion
    ? .notPermitted        // version matches what you sent; RLS filtered the write, not staleness
    : .versionConflict(current)  // version moved; feed (base, mine, current) to Reconciliation
```

Without this, every write a read-only account attempts surfaces as "someone else edited this" —
a confusing, actively misleading error for something that's actually a permissions problem.

## Auth: password grant vs. magic link, and reading the right claim

Two things worth knowing before they cost debugging time:

- **Magic link needs a mailbox that can receive mail.** If your test/seed accounts use addresses
  that can never receive email (or your project has `mailer_autoconfirm` disabled), the password
  grant (`grant_type=password` against `/auth/v1/token`) is the sign-in that can actually complete
  — magic link's own working assumption doesn't hold for accounts like that.
- **Read `app_metadata.role`, not the top-level `role` claim.** A JWT's top-level `role` claim is
  `authenticated` for every signed-in user regardless of your own app-level role — reading it
  instead of `app_metadata.role` makes every signed-in user look like an admin client-side (the
  database's own RLS still enforces correctly either way, but your UI would be lying to itself
  about what a user can do).

**Official SDK vs. plain REST calls.** The fork point deliberately skipped `supabase-swift` and
called Supabase's REST/RPC endpoints directly over `URLSession` — four endpoints (sign-in, refresh,
select, the `update_document` RPC) is the entire integration surface this project needs, and at
the time, adding a remote SPM dependency to a hand-maintained `.xcodeproj` was a real, specific
cost. That specific obstacle doesn't apply to a project using a generated or Xcode-managed project
(see `examples/ios-basic/`'s own `.xcodeproj`, built with XcodeGen) — for a new integration, the
official `supabase-swift` SDK is the more maintainable default; reaching for plain `URLSession`
calls the way the fork point did is a reasonable choice specifically when you want the exact wire
contract visible in your own code rather than behind an SDK's abstraction, not a default.

## Images: Supabase Storage

Not what the fork point did (it used a plain S3-compatible bucket) — this is Supabase's own
documented Storage API, real and verified, offered as the option for a team that wants one vendor
end to end rather than Postgres-here, images-somewhere-else.

Store images in a bucket under an object-key-shaped path (`doc-images/<uuid>.jpg`), exactly the
key that goes into the `Delta`'s image op — nothing here changes the storage contract's "object
keys only, never URLs" rule.

- **Public bucket**: `storage.from(bucket).getPublicUrl(path)` returns a permanent, unauthenticated
  URL — `PublicURLImageFetcher` covers this directly, pointed at the bucket's public base URL.
  **A public bucket is not the same as no access control**: `public = true` only skips the
  signed-URL step for *reads*; RLS policies on the `storage.objects` table still govern uploads,
  deletes, and can further restrict reads if you add a policy that does. Don't assume "public
  bucket" means "no RLS to write" — verify the bucket's actual policies before relying on that.
- **Private bucket**: `storage.from(bucket).createSignedUrl(path, expiresIn)` returns a
  time-limited URL. This needs a custom `ImageFetching` conformance (not
  `PublicURLImageFetcher`, which assumes a stable, unauthenticated URL) — one that calls the
  Storage API to mint a fresh signed URL before each fetch, since a cached signed URL expires.
- **RLS on `storage.objects`**: the same `is_admin()`-style policy pattern from the database
  section above applies directly — a policy on `storage.objects` scoped by
  `(storage.foldername(name))[1]` or a bucket-specific `auth.uid()` check governs who may upload
  images, independent of whatever policy governs the `documents` table itself.

For uploads, a `RichTextImageUploading` conformance wraps `storage.from(bucket).upload(path:data:)`
and returns the object key (the path within the bucket) it stored under — never the URL Storage
also hands back, per the same rule every other guide in this catalog states.
