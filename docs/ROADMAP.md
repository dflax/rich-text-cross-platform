# Roadmap

What's real, what's scoped but not built, and what's an open decision — written the night this
project was extracted, so the gap between "designed" and "shipped" stays honest as work
continues. Update this as items move between sections; don't let it silently go stale.

## Done and verified

- **`RichTextCore`** — ported from the fork point unchanged in logic (see `PROVENANCE.md`).
  83 tests green via plain `swift test` from the repo root — cross-platform, no simulator needed.
- **`RichTextEditor`** — extracted and decoupled from the fork point's backend-specific plumbing.
  Public API: `RichTextEditor` (SwiftUI view), `RichTextEditorConfiguration`,
  `RichTextImageUploading`, `ImageDownscaling`. 4 tests green via `xcodebuild test -scheme
  RichTextCrossPlatform-Package -destination 'platform=iOS Simulator,…'` (real `UITextView`,
  can't run under plain `swift test` on macOS — see the packaging note below for how this still
  builds cleanly there).
- **One `Package.swift` at the repo root, two products** (`RichTextCore`, `RichTextEditor`) —
  `RichTextEditor`'s source is wrapped in `#if canImport(UIKit)`, so `swift test` succeeds
  everywhere: on macOS that product simply compiles to an empty module and contributes 0 tests,
  rather than failing outright on an unconditional `import UIKit`. This replaced an intermediate
  two-separate-packages structure that fixed the same macOS-build problem but broke a single
  remote `.package(url:)` dependency being able to add both products — a `.package(url:)` always
  resolves one manifest at the repository root. Confirmed empirically before committing to it,
  not assumed. `ImageDownscaling` (referenced from the public, UIKit-gated
  `RichTextEditorConfiguration`) lives in `ImageDownscaler.swift` deliberately *outside* that
  guard, since it's a plain cross-platform value type — a lesson worth remembering when the macOS
  editor product is added: anything a UIKit-gated type's public API exposes has to itself be
  ungated or gated identically, or the two products won't compose.
- **Fixture corpus** — a shared copy at the repo root (`fixtures/`), the same one both
  `RichTextCore`'s own resource-bundled copy (`Tests/RichTextCoreTests/Resources/fixtures`,
  required by SPM's resource-bundling rules) and the web package's tests are proven against. The
  two Swift-side copies need to be kept in sync by hand until that's automated (see below).
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
- **License, minimum OS, and the macOS editor commitment** — see "Decided" below.

## Decided (2026-09-14)

- **License: MIT** — chosen specifically because it permits commercial use without restriction
  (this app is a real, intended commercial consumer). See `LICENSE`.
- **Minimum OS stays iOS 26 / macOS 26.** Not being lowered. Matches the fork point's own proven
  baseline; TextKit-2-on-`UITextView` compatibility below iOS 26 was never going to be verified
  work worth prioritizing over the macOS editor below.
- **A real macOS editor will be built, on `NSTextView`** — not just evaluated. This is now a
  requirement for the this app integration, not a someday-maybe. See "Scoped, not yet built" below
  for what that actually takes.

## Scoped, not yet built

Ordered by what unblocks the most other work.

1. **The macOS editor** (`NSTextView`-based), now committed rather than speculative. Real scope,
   not a rename of the iOS work:
   - Confirm `RichTextCore/NSDeltaCodec.swift`'s `NSAttributedString`/`NSTextAttachment`/
     `NSParagraphStyle`/`NSTextList` usage is genuinely AppKit-compatible today (it already has
     `#if canImport(AppKit)` branches in a few places, inherited from the fork point, but this has
     never actually been built or tested on macOS) — likely close to reusable as-is, needs
     verifying, not assuming.
   - A new product/target (e.g. `RichTextEditorMac`) mirroring `RichTextEditor`'s shape —
     `RichTextEditorModel`-equivalent, an `NSViewRepresentable` wrapping `NSTextView`, a toolbar —
     but not a shared implementation: `NSTextView`'s delegate pattern, selection model
     (`NSRange` via `NSTextView.selectedRange()` vs. `UITextView.selectedRange`), first-responder
     handling, and attachment/paste APIs all differ from `UITextView`'s in real, not cosmetic,
     ways. Expect to port the *design* (single-source-of-truth model, vocabulary enforcement via
     paste interception + a storage-delegate backstop, `FittedImageTextAttachment`-equivalent
     sizing) rather than the code.
   - Liquid Glass's `GlassEffectContainer`/`.glassEffect()` (the iOS toolbar's look) is available
     on macOS 26 too — worth checking whether `RichTextFormatBar`'s SwiftUI code can be shared
     directly rather than rewritten, since it doesn't touch UIKit types itself, only
     `RichTextEditorModel` (which won't be shared).
   - This becomes the third product from the one `Package.swift` — watch for the same "anything a
     platform-gated type's public API exposes must itself be ungated or gated identically" trap
     `ImageDownscaling` already hit once (see "Done and verified" above).
   - Needs its own README.md Scope-section update and `docs/ARCHITECTURE.md` update once real —
     don't leave the "iOS/iPadOS only" framing stale once this lands.
2. **Finish wrapping `examples/ios-basic`'s source in a real `.xcodeproj`.** The four Swift files
   (minimal / with-images / custom-toolbar / app entry) are written and manually verified against
   the real `RichTextEditor` API; the project-scaffolding tool needed a one-time manual approval
   click that wasn't available when this was written. See `examples/ios-basic/README.md` for the
   two-minute manual step, or have a session with Xcode MCP access retry `XcodeNewProject`.
3. **A web sample app** mirroring the iOS one's configuration variants
   (`configureImageBaseURL`, a demo `QuillHost` usage, a custom-toolbar-equivalent — Quill's own
   toolbar module config already *is* the "custom toolbar" story, so this is more "show it" than
   "build new capability").
4. **A build step for the web package** producing a publishable `dist/` (tsup or plain `tsc`) —
   it currently ships as source, `main`/`types` pointing straight at `src/index.ts`.
5. **Port the fork point's fuller round-trip test suite** to the web package —
   `test/round-trip.test.ts` proves byte-identity and vocabulary membership across the whole
   corpus (22 tests), which is the actual cross-platform-consistency proof, but doesn't yet cover
   every coalescing/idempotence/image-edge-case assertion `RichTextCoreTests` covers on the Swift
   side. See that package's own `README.md`.
6. **Automate keeping the two Swift-side fixture copies in sync** (repo-root `fixtures/`, used by
   the web package's tests, and `Tests/RichTextCoreTests/Resources/fixtures`, required by SPM's
   resource-bundling rules) — a script or a pre-commit check, so they can't silently drift.
7. **U1/U2/U6/U7-equivalent hands-on verification on real hardware**, ported from the fork
   point's own outstanding items — hanging indent and non-selectable markers under live editing,
   cross-editor consistency (well, cross-*platform* now: iOS-authored ↔ web-read), full
   toolbar/list-editing parity. The fork point never finished this pass before extraction (see
   that repo's own `TASK-034`); it needs redoing here since this is a different package with a
   different public API surface, not the same code under a new name. Once the macOS editor
   exists, its own equivalent pass is separate work, not covered by the iOS pass.
8. **CI** — GitHub Actions running `swift test` (cross-platform, `RichTextCore`),
   `xcodebuild test -scheme RichTextCrossPlatform-Package -destination 'platform=iOS Simulator,…'`
   (the full Swift suite, once the macOS editor lands this may need its own destination too), and
   `npm test`/`npm run typecheck` for the web package, on every PR. Not yet set up.
9. **CONTRIBUTING.md, issue/PR templates.** Open-source hygiene not yet done.
10. **Scrub remaining internal proof-point references** (`P1`–`P10`, "Build Order step N") out of
    code comments across `Sources/RichTextCore/`, `Tests/RichTextCoreTests/`, and
    `web/packages/rich-text-editor/src/`. Not sensitive (no secrets, checked before the repo went
    public) — just unpolished, since those numbers meant something in the fork point's own
    internal PRD and mean nothing to an outside reader here.

## Open decisions, not yet made

- **How to distribute this once it's more than one product's worth of platforms** — today's
  single `Package.swift`/multiple-products shape works cleanly for `RichTextCore` +
  `RichTextEditor` (+ the macOS product once built); if this ever needs to split (e.g. a
  genuinely separate release cadence per platform), that's a real decision to make deliberately,
  not a default to fall into.
- **Whether the fork point's SwiftUI/`TextEditor`-based editor is worth ever revisiting** —
  deliberately not ported (see `PROVENANCE.md`). If a future SDK closes the hanging-indent/
  non-selectable-marker gap `docs/ARCHITECTURE.md` describes, that changes the calculus; until
  then, carrying a third *iOS* editor implementation here (distinct from the macOS editor above,
  which targets a platform with no editor at all yet) would add API surface for no proven benefit.
