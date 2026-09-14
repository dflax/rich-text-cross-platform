# Postgres backend

A real, generic-Postgres implementation of the storage contract described in
[`docs/backends/README.md`](../../docs/backends/README.md) — no Supabase-specific assumptions,
though it runs unchanged on Supabase (which is just Postgres) and the migration notes where to
add Supabase's own RLS/`auth.uid()` conventions if you want them.

## Applying the migration

Plain Postgres (`psql`, any Postgres-compatible managed service):

```
psql "$DATABASE_URL" -f migrations/001_documents.sql
```

Supabase CLI:

```
supabase db push
```

(Supabase's own migration tooling just runs the same SQL — `gen_random_uuid()` needs the
`pgcrypto` extension, which Supabase enables by default; on plain Postgres run
`create extension if not exists pgcrypto;` first if it isn't already enabled.)

## What this gives you

- `documents` table: `id`, `title`, `delta` (jsonb, the canonical Quill Delta), a
  server-maintained `plain_text` for search/previews, `updated_at`, and `version`.
- `update_document(id, expected_version, title, delta)` — the one sanctioned write path.
  Returns zero rows when `expected_version` is stale; treat that as a conflict (feed it to
  `RichTextCore.Reconciliation.decide(base:mine:theirs:)` client-side), never retry blindly with
  the same expected version.
- Row-level security is included commented-out, since permissions are a product decision this
  project doesn't make for you — see the migration's own comments for a worked example.

## Image storage

Not part of this schema on purpose — `Delta` image ops carry an object key, not a URL (see the
storage contract's "Images" row), so image *bytes* live wherever you already put objects: S3,
a Backblaze B2 bucket, Cloudflare R2, or similar. Wire your chosen store to
`RichTextCore.ImageFetching` for reads and `RichTextEditor.RichTextImageUploading` for uploads —
`RichTextCore.PublicURLImageFetcher` already covers "plain HTTPS GET from a public bucket/CDN" if
that fits your setup; anything needing real authorization (signed URLs, bearer tokens) needs its
own `ImageFetching` conformance.
