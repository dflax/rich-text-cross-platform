# Roadmap

What's real, what's scoped but not built, and what's an open decision — written the night this
project was extracted, so the gap between "designed" and "shipped" stays honest as work
continues. Update this as items move between sections; don't let it silently go stale.

## Done and verified

- **`RichTextCore`** (`swift/RichTextCore/`) — ported from the fork point unchanged in logic (see
  `PROVENANCE.md`). 83 tests green via plain `swift test` — cross-platform, no simulator needed.
- **`RichTextEditor`** (`swift/RichTextEditor/`) — extracted and decoupled from the fork point's
  backend-specific plumbing, packaged separately from `RichTextCore` (see this doc's Open
  Decisions for why) with a local path dependency on it. Public API: `RichTextEditor` (SwiftUI
  view), `RichTextEditorConfiguration`, `RichTextImageUploading`, `ImageDownscaling`. 4 tests
  green via `xcodebuild test -scheme RichTextEditor -destination 'platform=iOS Simulator,…'`
  (real `UITextView`, can't run under plain `swift test` on macOS).
- **Fixture corpus** — a shared copy at the repo root (`fixtures/`), the same one both the Swift
  package's own resource-bundled copy and the web package's tests are proven against. The two
  Swift-side copies (repo root and `swift/RichTextCore/Tests/.../Resources/fixtures`) need to be
  kept in sync
  by hand until that's automated — see "Scoped, not yet built" below.
- **Postgres backend** — see `backends/postgres/`.
- **Web package** (`web/packages/rich-text-editor`) — `delta.ts`/`vocabulary.ts`/`quill-setup.ts`/
  `image-key.ts`/`QuillHost.tsx` ported from the fork point's `web/` app and genericized (no more
  B2-specific naming, a configurable image base URL instead of a hardcoded bucket). 22 tests
  green (`npm test`), including byte-identical round-trip and vocabulary-membership checks
  against the *same* fixture corpus the Swift package uses — the actual cross-platform-
  consistency proof, not just a claim. `npx tsc --noEmit` clean. Ships as TypeScript source
  (no build step yet) — see below.
- **`docs/backends/mysql.md`, `mongodb.md`, `firebase.md`** — written guidance mapping the
  storage contract (`docs/backends/README.md`) onto each store.

## Scoped, not yet built

Ordered by what unblocks the most other work.

1. **Finish wrapping `examples/ios-basic`'s source in a real `.xcodeproj`.** The four Swift files
   (minimal / with-images / custom-toolbar / app entry) are written and manually verified against
   the real `RichTextEditor` API; the project-scaffolding tool needed a one-time manual approval
   click that wasn't available when this was written. See `examples/ios-basic/README.md` for the
   two-minute manual step, or have a session with Xcode MCP access retry `XcodeNewProject`.
2. **A web sample app** mirroring the iOS one's three configuration variants
   (`configureImageBaseURL`, a demo `QuillHost` usage, a custom-toolbar-equivalent — Quill's own
   toolbar module config already *is* the "custom toolbar" story, so this is more "show it" than
   "build new capability").
3. **A build step for the web package** producing a publishable `dist/` (tsup or plain `tsc`) —
   it currently ships as source, `main`/`types` pointing straight at `src/index.ts`.
4. **Port the fork point's fuller round-trip test suite** to the web package —
   `test/round-trip.test.ts` proves byte-identity and vocabulary membership across the whole
   corpus (22 tests), which is the actual cross-platform-consistency proof, but doesn't yet cover
   every coalescing/idempotence/image-edge-case assertion `RichTextCoreTests` covers on the Swift
   side. See that package's own `README.md`.
5. **Automate keeping the two Swift-side fixture copies in sync** (repo-root `fixtures/`, used by
   the web package's tests, and `swift/RichTextCore/Tests/RichTextCoreTests/Resources/fixtures`, required by
   SPM's resource-bundling rules) — a script or a pre-commit check, so they can't silently drift.
6. **U1/U2/U6/U7-equivalent hands-on verification on real hardware**, ported from the fork
   point's own outstanding items — hanging indent and non-selectable markers under live editing,
   cross-editor consistency (well, cross-*platform* now: iOS-authored ↔ web-read), full
   toolbar/list-editing parity. The fork point never finished this pass before extraction (see
   that repo's own `TASK-034`); it needs redoing here since this is a different package with a
   different public API surface, not the same code under a new name.
7. **CI** — GitHub Actions running `swift test` for `RichTextCore`,
   `xcodebuild test -scheme RichTextEditor -destination 'platform=iOS Simulator,…'` (from `swift/RichTextEditor/`)
   for the full Swift suite, and `npm test`/`npm run typecheck` for the web package, on every PR.
   Not yet set up.
8. **CONTRIBUTING.md, issue/PR templates, a real `LICENSE`** — open-source hygiene not yet done;
   see README.md's License section for the one open decision (MIT vs. something else) blocking
   the last of these.

## Open decisions, not yet made

- **How to distribute two Swift packages from one repo.** `RichTextCore` and `RichTextEditor`
  are separate packages (`swift/RichTextCore/`, `swift/RichTextEditor/`) so `RichTextCore`'s own
  `swift test` stays fast and simulator-free — a single combined package made *every* `swift
  test` invocation try (and fail on macOS) to build the UIKit-only editor target too, since `swift
  test` always builds a package's entire target graph regardless of `--filter`. The real
  consequence: a remote `.package(url:)` dependency always resolves one `Package.swift` at the
  repository root, so a consumer can't add both packages from this one repo via a normal remote
  dependency today — only by local path (submodule/vendoring), as `README.md`'s Quick Start
  shows. Splitting into two published repositories is the likely eventual fix; not yet decided.
- **License.** MIT is the default lean (permissive, standard for exactly this kind of dev tool);
  Apache-2.0's explicit patent grant is the other real candidate given commercial consumers
  (this app). Needs the maintainer's call, not an assumption baked in silently.
- **Minimum OS version.** Currently iOS 26 / macOS 26, matching the fork point's own proven
  baseline (`RichTextEditor`'s default toolbar uses the Liquid Glass API, iOS 26+; TextKit-2-on-
  `UITextView` compatibility below iOS 26 has been *assumed*, not verified, by this project).
  Lowering this — likely to wherever TextKit 2 first shipped, iOS 16 — is real, valuable,
  separately-schedulable work: verify hanging indent/list markers actually render correctly
  there, and make the toolbar's Liquid Glass look opt-in (`configuration.toolbar` already makes a
  replacement possible; the remaining piece is a non-Liquid-Glass *default* for pre-26 targets).
- **Whether to eventually build a real `NSTextView`-based macOS editor**, closing the gap
  `README.md`'s Scope section and `docs/ARCHITECTURE.md` name explicitly. Worth real evaluation,
  not an assumed yes — `NSTextView` is TextKit-based too, so the `RichTextCore` codec layer is
  likely close to reusable, but the editor-model/toolbar layer would need its own AppKit-specific
  work mirroring what `RichTextEditor` does for UIKit, not a shared implementation.
- **Whether the fork point's SwiftUI/`TextEditor`-based editor is worth ever revisiting** —
  deliberately not ported (see `PROVENANCE.md`). If a future SDK closes the hanging-indent/
  non-selectable-marker gap `docs/ARCHITECTURE.md` describes, that changes the calculus; until
  then, carrying two editor implementations here would double the API surface for no proven
  benefit.
