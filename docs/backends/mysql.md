# MySQL

Guidance, not shipped code — see [`README.md`](README.md) for why this project doesn't ship an
adapter per store. Mapping the [storage contract](README.md) onto MySQL:

## Schema

```sql
create table documents (
  id          char(36)     not null primary key,           -- or bigint auto_increment
  title       varchar(255) not null default '',
  delta       json         not null,                        -- MySQL 5.7+: native JSON type
  plain_text  text,                                          -- see "Derived plain text" below
  updated_at  timestamp    not null default current_timestamp
                           on update current_timestamp,
  version     bigint       not null default 1
) engine = InnoDB;
```

`json` columns store as an internal binary format and validate on write — invalid JSON is
rejected at the database, not silently accepted. `on update current_timestamp` keeps `updated_at`
correct without your application code having to remember to set it.

## Optimistic concurrency

MySQL has no equivalent to Postgres's `returning` on a conditional `update`, so check the
affected-row count explicitly:

```sql
UPDATE documents
   SET title = ?, delta = ?, version = version + 1
 WHERE id = ? AND version = ?;
-- Then check: if the driver reports 0 rows affected, the expected version was stale --
-- surface that as a conflict (feed it to RichTextCore.Reconciliation client-side),
-- never retry blindly with the same expected version.
```

Wrap the update in a transaction if your driver doesn't guarantee affected-row-count reporting is
consistent with the write actually having committed under your isolation level.

## Derived plain text

Two options, in order of preference:

1. **A generated column**, if your MySQL version's JSON path functions can express "concatenate
   every string `insert` in `delta->'$.ops'`, in order" — MySQL's `JSON_TABLE` (8.0+) can do this,
   though it's more verbose than Postgres's `jsonb_array_elements`. Worth it if you want
   `plain_text` to always be correct with no application-level trigger to maintain.
2. **Application-level**, computed in the same request/transaction that writes `delta` — simpler,
   works on any MySQL version, but now something your application code has to remember to do on
   every write path, not something the database guarantees.

## Images

Unaffected by choice of relational database — see the storage contract's "Images" row. Point
`RichTextCore.PublicURLImageFetcher` or your own `ImageFetching` conformance at whatever object
store you use; nothing here is MySQL-specific.
