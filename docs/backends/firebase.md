# Firebase (Firestore + Storage)

Guidance, not shipped code — see [`README.md`](README.md) for why this project doesn't ship an
adapter per store. Mapping the [storage contract](README.md) onto Firebase:

## Document shape (Firestore)

```
documents/{documentId}
  title: string
  delta: map            // Quill Delta as a nested map -- see note below
  plainText: string
  updatedAt: Timestamp
  version: number
```

**Note on `delta` as a Firestore map**: Firestore documents are maps of typed fields, not raw
JSON — a `Delta`'s `ops` array (each op a map with `insert` and optional `attributes`) maps
directly onto Firestore's own array-of-maps support, so this is a natural fit, not a workaround.
If you'd rather store the canonical JSON string byte-for-byte (e.g. to keep the exact
serialization your round-trip tests check against, rather than trusting Firestore's own
map-to-JSON reconstruction to match it), store `delta` as a `string` field holding the JSON
instead — either is a valid implementation of the contract; pick based on whether you need to
query into `delta`'s structure from security rules or Cloud Functions (map) or need exact byte
fidelity (string).

## Optimistic concurrency

Firestore transactions are the natural fit — read-then-conditionally-write, atomically:

```js
await runTransaction(db, async (tx) => {
  const ref = doc(db, "documents", documentId);
  const snapshot = await tx.get(ref);
  if (snapshot.data().version !== expectedVersion) {
    throw new StaleVersionError(); // surface as a conflict client-side --
                                    // feed it to RichTextCore.Reconciliation,
                                    // never retry blindly with the same expectedVersion
  }
  tx.update(ref, { title, delta, plainText, updatedAt: serverTimestamp(), version: expectedVersion + 1 });
});
```

## Derived plain text

Compute `plainText` client-side in the same write that sets `delta` (simplest), or in a Cloud
Function triggered `onWrite` if you want it guaranteed server-derived the way the Postgres
migration's trigger does — Firestore has no native generated-field mechanism, so "server-derived"
here means "a Cloud Function did it," not "the database enforced it."

## Images (Firebase Storage)

Store images in Firebase Storage under an object-key-shaped path (e.g. `doc-images/<uuid>.jpg`)
— the same key goes into the `Delta`'s image op, never a download URL (see the storage contract's
"Images" row for why). Two ways to wire `ImageFetching`:

- If Storage objects are readable via a public, unauthenticated download URL (a fixed base URL +
  the object path), `RichTextCore.PublicURLImageFetcher` covers this directly.
- If reads need Firebase Auth-scoped access, write your own `ImageFetching` conformance calling
  the Firebase Storage SDK's own authenticated download API instead of a plain `URLSession` GET.

For uploads, a `RichTextImageUploading` conformance wraps `Storage.putData(_:metadata:)` (or the
equivalent for your platform's Firebase SDK) and returns the object key it stored under.
