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

## Packaging — verified 2026-09-14

Daniel asked whether this genuinely works as an Xcode/SPM drop-in, and which other package
managers are worth supporting. Tested directly rather than reasoned about:

- **SPM remote-dependency consumption works.** A scratch consumer package with
  `.package(url: "https://github.com/dflax/rich-text-cross-platform", branch: "main")` and both
  products as dependencies resolved and built cleanly (`swift build`, both `RichTextCore` and
  `RichTextEditor` compiled). Confirmed as an actual `swift build` against the real public URL,
  not inferred from `xcodebuild` runs against the local checkout.
- **The README's own Quick Start snippet was broken** — `from: "0.1.0")` fails to resolve, because
  no tag has ever been pushed (`git ls-remote --tags origin` is empty). Confirmed the failure
  directly: `error: Dependencies could not be resolved because no versions of
  'rich-text-cross-platform' match the requirement 0.1.0..<1.0.0`. Fixed the README to
  `branch: "main"` with a note to switch to `from:` once a release is tagged — **cutting a
  `v0.1.0` tag is Daniel's call**, not something to do silently as a side effect of a docs fix.
- **Other Swift package managers: none recommended.** SPM is Apple's own supported path and the
  one that actually got verified above. CocoaPods is in maintenance mode industry-wide; Carthage
  is effectively inactive. Adding a `.podspec` to a package whose whole premise is "clean modern
  drop-in" is ongoing maintenance for a shrinking audience, for no capability SPM lacks here.
- **Web package managers: not actually a decision to make.** npm/yarn/pnpm are three clients over
  one registry and one `package.json` — supporting all three is automatic once the package is
  published, not three separate integrations. The real gap is that nothing is published yet (no
  `dist/`, not on the npm registry) — see item 4 below. Once that's done, npm/yarn/pnpm all work
  identically with zero extra work.

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

1. **The macOS editor** (`NSTextView`-based), now committed rather than speculative. Verified
   2026-09-14 by actually running the suite and reading the call sites, not by inference:
   - **`RichTextCore` is already proven on AppKit — not "likely reusable," actually verified.**
     Plain `swift test` on macOS has no `UIKit` at all, so every one of its 83 green tests —
     including `"A decoded image attachment fits the text container's width instead of rendering
     at its raw pixel size"`, the full `NSTextList` instance-identity/renumbering suite, and
     `VocabularyTextStorageDelegate`'s clamp/re-entrancy tests — already compiled and ran through
     the `#elseif canImport(AppKit)` branches (`FittedImageTextAttachment.attachmentBounds`,
     `PlatformTextStorageEditActions`, `NSParagraphStyle`/`NSTextList` construction). Nothing left
     to confirm here; the codec layer is not a risk for this work.
   - **The real, non-cosmetic porting cost is `selectedRange`.** `RichTextEditorModel` reads or
     writes `textView.selectedRange` — a single `NSRange` — at 20 call sites (`currentLineStyle`,
     `isBoldActive`/`isItalicActive`/`isUnderlineActive`/`isStrikeActive`, `linkEditContext`,
     `applyLink`, `setLineStyle`, `insertImage`, the coordinator's selection callback, etc.).
     `NSTextView` has no equivalent single-range property — `selectedRanges: [NSValue]` exists
     because AppKit supports discontiguous multi-range selection. **Decision needed before writing
     the mac model**: collapse to `selectedRanges.first` at the one point where the mac coordinator
     reads selection (matching this editor's existing single-range UX and vocabulary — nothing here
     is designed around multi-range selection anyway), rather than threading `[NSValue]` through
     all 20 call sites. Recommendation: collapse. Record the choice in the mac model's doc comment
     so it reads as a decision, not an oversight, if someone later wonders why multi-select does
     nothing useful.
   - **Delegate surface is a rewrite, not a rename** — confirmed by grep, not memory:
     `RichTextTextView`'s `Coordinator: UITextViewDelegate` implements `textViewDidChange(_:)` and
     `textViewDidChangeSelection(_:)`. `NSTextViewDelegate` has different method shapes for the
     first (AppKit's text-change notification comes through `NSTextDelegate`, not the same
     signature) — verify the exact current signature against the macOS 26 SDK when writing this,
     don't assume from an iOS mental model.
   - **`isScrollEnabled = false` + `intrinsicContentSize` auto-sizing has no AppKit equivalent.**
     `NSTextView` doesn't expose `isScrollEnabled`; it's normally hosted inside an `NSScrollView`.
     The auto-growing-height trick `RichTextTextView` uses for the iOS editor needs a genuinely
     different mechanism on macOS (e.g. observing the text container's used rect and resizing the
     hosting view), not a ported property.
   - **`RichTextFormatBar` is confirmed toolbar-shareable in principle** (it only imports
     `SwiftUI`, no `UIKit` types — checked directly), but it's currently wrapped inside
     `RichTextEditor`'s own `#if canImport(UIKit)` file guard alongside everything else, and its
     button actions call directly into `RichTextEditorModel` (the iOS-specific class). To actually
     share the file rather than just observe that it *could* be shared, extract a small protocol
     (e.g. `RichTextEditingModel`) that both `RichTextEditorModel` and the new mac model conform
     to, and have the format bar depend on the protocol — otherwise "shareable" stays theoretical.
   - Liquid Glass's `GlassEffectContainer`/`.glassEffect()` is available on macOS 26 too, so the
     toolbar's look carries over once the protocol above makes the file genuinely shared.
   - New product/target (e.g. `RichTextEditorMac`) — third product from the one `Package.swift`.
     Watch for the same "anything a platform-gated type's public API exposes must itself be
     ungated or gated identically" trap `ImageDownscaling` already hit once (see "Done and
     verified" above).
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
