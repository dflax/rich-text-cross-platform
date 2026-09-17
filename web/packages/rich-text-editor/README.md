# @rich-text-cross-platform/editor

A [Quill](https://quilljs.com/) 2.x wrapper enforcing the same small formatting vocabulary the
Swift `RichTextEditor` package enforces, reading and writing the same Quill Delta JSON — see
[`docs/ARCHITECTURE.md`](../../../docs/ARCHITECTURE.md).

**Status: real, tested, and built for publishing.** `npm run build` (via `tsup`) produces a real
`dist/` — an ESM bundle plus `.d.ts` declarations — and `main`/`module`/`types`/`exports` all
point at it. `react`, `react-dom`, and `quill` stay peer dependencies, not bundled. Not yet
published to the npm registry itself — see `docs/ROADMAP.md`.

## What's here

- `delta.ts` — the Delta model: types, decode/encode, coalescing. The JS twin of
  `RichTextCore/Delta.swift` and `NSDeltaCodec.swift`'s canonical-JSON contract — byte-identical
  output for the same document is the whole point (see `test/round-trip.test.ts`, which proves
  it against the same fixture corpus the Swift package uses).
- `vocabulary.ts` — `vocabularyViolations()`/`isWithinVocabulary()`/`clampToVocabulary()`, the
  backstop validation layer, mirroring `RichTextCore/Vocabulary.swift`.
- `quill-setup.ts` — the constrained Quill configuration: a `formats` allowlist restricted to
  exactly the shared vocabulary (strips out-of-vocabulary formats arriving via paste at the Quill
  level), a custom image blot that keeps a Delta image op as an object key, never a URL or a
  base64 blob, and `installPasteGuards()`, which drops every pasted `<img>` outright — see
  `docs/guides/vocabulary-enforcement.md`'s "Web" section for why a pasted image can never become
  one of our storage-key embeds.
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

## Building and testing

```
npm install
npm run build     # tsup -> dist/index.js, dist/index.d.ts
npm test          # round-trip + vocabulary tests against the shared fixture corpus
npm run typecheck
```

## Using this before it's on the npm registry

Not published yet — see below — but you don't need the registry to consume it. `package.json`'s
`prepare` script means `dist/` gets built automatically wherever npm runs its own lifecycle
scripts, which covers both routes below (verified end to end, not assumed):

- **A tarball.** `npm run build && npm pack` produces `rich-text-cross-platform-editor-<version>.tgz`.
  `npm install <path-or-url-to-that-file>` works exactly like installing from the registry —
  verified by installing the packed tarball into a scratch project (both from a local path and
  served over HTTP, simulating a GitHub Release asset URL) and confirming every expected export
  imports correctly. Attaching the `.tgz` to a GitHub Release and pointing consumers at that
  release-asset URL is the most reproducible version of this.
- **A plain git dependency**, if you only need the repo root's two Swift products and don't
  specifically need this web package: `npm install
  "git+https://github.com/dflax/rich-text-cross-platform.git#main"` works for a package whose
  `package.json` sits at the *root* of the repo. It does **not** work for this package as-is,
  because it lives in a subdirectory (`web/packages/rich-text-editor`) — the commonly-cited
  `#main?subdirectory=...` query-parameter syntax was tested directly against this repo and
  **does not work** with plain npm (11.19.1 here): npm treated the whole string after `#` as a
  literal (and invalid) git ref rather than splitting on `?subdirectory=`. Don't rely on it
  without re-verifying against whatever npm version you're actually running.

## Not yet done (see `docs/ROADMAP.md`)

- Publishing to the npm registry itself (the build step and the no-registry workarounds above are
  done; `npm publish` isn't).
- Image upload wiring / a sample app showing multiple configurations (the iOS side has this in
  `examples/rich-text-editor-demo/`; the web equivalent doesn't exist yet).
- Porting the fork point's full round-trip test suite (this package's `test/round-trip.test.ts`
  is a real but smaller subset — it proves byte-identity and vocabulary membership across the
  whole corpus, not yet the fork point's additional coalescing/idempotence/image-edge-case
  assertions that `RichTextCoreTests` covers on the Swift side).
