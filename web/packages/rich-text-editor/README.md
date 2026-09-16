# @rich-text-cross-platform/editor

A [Quill](https://quilljs.com/) 2.x wrapper enforcing the same small formatting vocabulary the
Swift `RichTextEditor` package enforces, reading and writing the same Quill Delta JSON — see
[`docs/ARCHITECTURE.md`](../../../docs/ARCHITECTURE.md).

**Status: real, tested, not yet built for publishing.** This ships as TypeScript source
(`main`/`types` point at `src/index.ts` directly) — your bundler needs to handle `.ts`/`.tsx`
itself, since there's no compiled `dist/` yet. See `docs/ROADMAP.md`.

## What's here

- `delta.ts` — the Delta model: types, decode/encode, coalescing. The JS twin of
  `RichTextCore/Delta.swift` and `NSDeltaCodec.swift`'s canonical-JSON contract — byte-identical
  output for the same document is the whole point (see `test/round-trip.test.ts`, which proves
  it against the same fixture corpus the Swift package uses).
- `vocabulary.ts` — `vocabularyViolations()`/`isWithinVocabulary()`/`clampToVocabulary()`, the
  backstop validation layer, mirroring `RichTextCore/Vocabulary.swift`.
- `quill-setup.ts` — the constrained Quill configuration: a `formats` allowlist restricted to
  exactly the shared vocabulary (strips out-of-vocabulary formats arriving via paste at the Quill
  level), and a custom image blot that keeps a Delta image op as an object key, never a URL or a
  base64 blob.
- `image-key.ts` — resolves an object key to a fetchable URL at render time; call
  `configureImageBaseURL(url)` once at startup. Mirrors `RichTextCore.PublicURLImageFetcher`.
- `QuillHost.tsx` — the React component. Dynamically imports Quill (it touches `document` at
  module scope, so this must not run during server rendering).

## Quick start

```tsx
import { QuillHost, configureImageBaseURL, type Delta } from "@rich-text-cross-platform/editor";

configureImageBaseURL("https://your-bucket.example.com"); // once, at app startup

function Editor({ initialDelta, onSave }: { initialDelta: Delta; onSave: (d: Delta) => void }) {
  return (
    <QuillHost
      initialDelta={initialDelta}
      onReady={(api) => {
        // api.getDelta() / api.setDelta(delta) whenever you need to read/write
      }}
    />
  );
}
```

## Testing

```
npm install
npm test         # round-trip + vocabulary tests against the shared fixture corpus
npm run typecheck
```

## Not yet done (see `docs/ROADMAP.md`)

- A real build step producing a publishable `dist/`.
- Image upload wiring / a sample app showing multiple configurations (the iOS side has this in
  `examples/rich-text-editor-demo/`; the web equivalent doesn't exist yet).
- Porting the fork point's full round-trip test suite (this package's `test/round-trip.test.ts`
  is a real but smaller subset — it proves byte-identity and vocabulary membership across the
  whole corpus, not yet the fork point's additional coalescing/idempotence/image-edge-case
  assertions that `RichTextCoreTests` covers on the Swift side).
