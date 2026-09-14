# MongoDB

Guidance, not shipped code — see [`README.md`](README.md) for why this project doesn't ship an
adapter per store. Mapping the [storage contract](README.md) onto MongoDB:

## Document shape

```json
{
  "_id": "…",
  "title": "",
  "delta": { "ops": [ { "insert": "\n" } ] },
  "plainText": "",
  "updatedAt": { "$date": "…" },
  "version": 1
}
```

`delta` stores as a native embedded document — no serialization step needed, since Quill's Delta
format is already just JSON. This is arguably MongoDB's best natural fit among the databases
covered here for exactly that reason.

## Optimistic concurrency

MongoDB's `findOneAndUpdate` with a filter on the expected version *is* the conditional update —
no separate row-count check needed, since a filter that matches nothing simply returns no
document:

```js
const result = await documents.findOneAndUpdate(
  { _id: id, version: expectedVersion },
  {
    $set: { title, delta, updatedAt: new Date() },
    $inc: { version: 1 },
  },
  { returnDocument: "after" }
);
// result is null when expectedVersion was stale -- surface that as a conflict
// (feed it to RichTextCore.Reconciliation client-side), never retry blindly
// with the same expectedVersion.
```

## Derived plain text

No generated-column equivalent in MongoDB — compute `plainText` in application code (walk
`delta.ops`, concatenate every string `insert` in order) in the same write path that sets
`delta`, or use a change stream / Atlas trigger to derive it asynchronously if you're comfortable
with `plainText` being eventually consistent rather than always in sync with the write that
produced it.

## Indexing for search/preview lists

Add a text index on `plainText` (`db.documents.createIndex({ plainText: "text" })`) rather than
querying into `delta`'s nested structure directly — the whole reason `plainText` exists per the
storage contract is so list views and search never need to decode a `Delta` to work.

## Images

Unaffected by choice of database — see the storage contract's "Images" row. Point
`RichTextCore.PublicURLImageFetcher` or your own `ImageFetching` conformance at whatever object
store you use (GridFS is possible for images but not recommended here — it optimizes for a
different problem than "serve a static file over HTTP", which is all `ImageFetching` needs).
