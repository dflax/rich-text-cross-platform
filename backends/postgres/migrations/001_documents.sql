-- Rich Text Cross-Platform — generic Postgres schema for the storage contract in
-- docs/backends/README.md. Deliberately plain Postgres, not Supabase-specific: no
-- auth.users/auth.jwt() assumptions. If you're on Supabase, swap owner_id's reference
-- and the RLS policy predicates below for auth.uid()/auth.jwt() — everything else applies
-- unchanged. If you're on plain Postgres (or RDS, Cloud SQL, etc. running Postgres),
-- this runs as-is minus the "if you have a users table" bits, which are commented.

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------

create table if not exists documents (
  id          uuid        primary key default gen_random_uuid(),
  -- Uncomment and adapt if you have a users table to reference:
  -- owner_id    uuid        references users (id) on delete cascade,
  title       text        not null default '',
  -- Canonical Quill Delta JSON. Image embeds carry an object key only, never a URL —
  -- see docs/backends/README.md's "Images" row for why.
  delta       jsonb       not null default '{"ops":[{"insert":"\n"}]}'::jsonb,
  -- Denormalized plain text, derived from `delta` by trigger below. For list views and
  -- search only — never write this column directly, and never let a client decode
  -- `delta` client-side just to populate a preview.
  plain_text  text        not null default '',
  updated_at  timestamptz not null default now(),
  -- Optimistic concurrency token — see update_document() below. A stale expected
  -- version matches zero rows rather than silently overwriting a newer write.
  version     bigint      not null default 1
);

comment on table documents is
  'One Quill Delta document per row. delta is the canonical format on every client.';
comment on column documents.delta is
  'Canonical Quill Delta JSON (ops array). Image embeds reference an object key only.';
comment on column documents.plain_text is
  'Derived from delta at write time by trigger. For list rows / search only. Do not write directly.';
comment on column documents.version is
  'Optimistic concurrency token, bumped only by update_document(). A stale expected version affects zero rows -- the client surfaces that as a conflict, per RichTextCore.Reconciliation.';

-- ---------------------------------------------------------------------------
-- Derived fields: plain_text + updated_at
-- ---------------------------------------------------------------------------

-- Concatenates every string `insert` in the Delta, in op order. WITH ORDINALITY is
-- load-bearing: jsonb_array_elements has no guaranteed output order for string_agg
-- without it, so the derived text could silently scramble.
--
-- A trigger, not a GENERATED column: a plpgsql function that walks jsonb cannot
-- honestly be marked IMMUTABLE, which generated columns require.
create or replace function documents_derive_fields()
returns trigger
language plpgsql
as $$
begin
  new.plain_text := coalesce(
    (
      select string_agg(t.op ->> 'insert', '' order by t.ord)
      from jsonb_array_elements(coalesce(new.delta -> 'ops', '[]'::jsonb))
             with ordinality as t(op, ord)
      where jsonb_typeof(t.op -> 'insert') = 'string'
    ),
    ''
  );
  new.updated_at := now();
  -- This trigger must never touch new.version -- update_document() owns the bump.
  -- A second bump here would desynchronize every client's expected version.
  return new;
end;
$$;

drop trigger if exists documents_derive_fields on documents;
create trigger documents_derive_fields
before insert or update on documents
for each row execute function documents_derive_fields();

-- ---------------------------------------------------------------------------
-- Optimistic concurrency (last-write-wins with a version check)
-- ---------------------------------------------------------------------------

-- The sanctioned write path: read `version`, pass it back as p_expected_version, and
-- a stale value matches no row -- an empty result set, which the client surfaces as a
-- conflict via RichTextCore.Reconciliation rather than silently overwriting.
create or replace function update_document(
  p_id               uuid,
  p_expected_version bigint,
  p_title            text,
  p_delta            jsonb
)
returns setof documents
language sql
as $$
  update documents
     set title   = p_title,
         delta   = p_delta,
         version = version + 1
   where id = p_id
     and version = p_expected_version
  returning *;
$$;

comment on function update_document is
  'The only sanctioned write path. Returns zero rows if p_expected_version is stale -- the caller must treat an empty result as a conflict, never retry blindly with the same expected version.';

-- ---------------------------------------------------------------------------
-- Row-level security (Supabase / Postgres RLS) -- OPTIONAL, adapt to your auth model
-- ---------------------------------------------------------------------------

-- Uncomment and adapt once you have real auth. Shown here as a worked example, not
-- because this project has an opinion about your permission model -- see
-- docs/backends/README.md's "What this project does not prescribe."
--
-- alter table documents enable row level security;
--
-- create policy documents_select_authenticated
--   on documents for select
--   to authenticated
--   using (true);
--
-- create policy documents_write_owner
--   on documents for all
--   to authenticated
--   using (owner_id = auth.uid())
--   with check (owner_id = auth.uid());
