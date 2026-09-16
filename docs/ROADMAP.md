# Roadmap

What's real, what's scoped but not built, and what's an open decision — written the night this
project was extracted, so the gap between "designed" and "shipped" stays honest as work
continues. Update this as items move between sections; don't let it silently go stale.

## Done and verified

- **`RichTextCore`** — ported from the fork point unchanged in logic (see `PROVENANCE.md`).
  83 tests green via plain `swift test` from the repo root — cross-platform, no simulator needed.
- **`RichTextEditor`, on iOS/iPadOS, macOS, *and* visionOS** — one public API (`RichTextEditor`,
  `RichTextEditorModel`, `RichTextTextView`, `RichTextEditorConfiguration`,
  `RichTextImageUploading`, `ImageDownscaling` — the same type names on every platform), backed by
  `UITextView` on iOS/iPadOS/visionOS and a real `NSTextView` on macOS, both on TextKit 2. The
  macOS half was built 2026-09-14, not just scoped — see "The macOS editor, built and verified"
  below for what shipped and the three real bugs actually launching it caught. visionOS support
  was built and verified 2026-09-15 — see "visionOS support, built and verified" below; it needed
  no new text-editing implementation (visionOS shares UIKit with iOS), only a toolbar-chrome and
  -placement change. 4 iOS tests (real, attached `UITextView`) + 6 macOS tests (real, attached
  `NSTextView`) green via `xcodebuild test -scheme RichTextCrossPlatform-Package
  -destination 'platform=iOS Simulator,…'` and `-destination 'platform=macOS'` respectively —
  neither runs under plain `swift test` on the *other* platform, but the macOS half **does** run
  under plain `swift test` on this machine
  (AppKit is native here), unlike the iOS half.
- **One `Package.swift` at the repo root, two products** (`RichTextCore`, `RichTextEditor`) — no
  third "Mac" product. `RichTextEditor`'s iOS files stay wrapped in `#if canImport(UIKit)`; its
  new macOS files (`RichTextEditorModelMac.swift`, `RichTextTextViewMac.swift`) are wrapped in
  `#if canImport(AppKit)` and declare **the same public type names** (`RichTextEditorModel`,
  `RichTextTextView`) as their iOS counterparts. Since the two guards are mutually exclusive per
  build target, this compiles cleanly as one name resolving to a different concrete
  implementation per platform — the exact pattern `RichTextCore`'s `PlatformFont`/`PlatformImage`/
  `PlatformColor` already established, scaled up to whole types. This superseded an earlier plan
  (see prior revisions of this file) to add a third `RichTextEditorMac` product behind a shared
  `RichTextEditingModel` protocol — unnecessary once the same-name-different-file trick was
  actually tried, and worse for consumers (one type to import and reference either way, not two).
  `RichTextFormatBar.swift` lost its `#if canImport(UIKit)` guard entirely once this landed — it
  only ever imported `SwiftUI`, so one file now serves both platforms unchanged. `ImageDownscaling`
  living in `ImageDownscaler.swift`, deliberately outside any platform guard, is exactly why this
  composed cleanly: the trap this note used to warn about (a platform-gated type's public API
  exposing an ungated dependency) never actually got hit building the macOS half, because that
  lesson was already applied.
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
- **`docs/backends/mysql.md`, `mongodb.md`, `firebase.md`, `cloudkit.md`, `supabase.md`,
  `powersync.md`** — written guidance mapping the storage contract (`docs/backends/README.md`)
  onto each store. `cloudkit.md` (added 2026-09-15) is verified by direct compilation against the
  real CloudKit SDK (`CKError.serverRecord`/`.clientRecord`/`.ancestorRecord`,
  `CKRecord.recordChangeTag`, `CKRecord.ID(recordName:zoneID:)`, `CKDatabase.save(_:)` async,
  `CKAsset`, all confirmed to exist and typecheck, not assumed from documentation), and covers the
  one decision none of the other guides force: private vs. shared vs. public database.
  `supabase.md` (added 2026-09-15) is grounded in the fork point's own real Supabase integration,
  not generic advice — including a real, non-obvious lesson that an empty result from
  `update_document()` is ambiguous under RLS (stale version vs. a blocked write look identical) in
  a way it isn't on plain Postgres. `powersync.md` (added 2026-09-15) is verified by resolving
  PowerSync's actual Swift SPM package and reading its shipped source/demo code directly.
  `docs/backends/CATALOG.md` covers the fuller provider landscape beyond these guides.
- **License, minimum OS, and the macOS editor commitment** — see "Decided" below.
- **Scrubbed internal proof-point references** (`P1`–`P10`, `U1`–`U7`, "Build Order step N", and
  stale pre-extraction type names like `UIKitEditorModel`/`DeltaCodec`/`SegmentedDocument`) out of
  every doc comment in `Sources/`, `Tests/`, and `web/packages/rich-text-editor/src/`. These
  referenced files (`PRD.md`, `docs/PRD-uikit-comparison-editor.md`, `project_context.md`) and
  types that only exist in the private `rich-text-poc` fork point — dead ends for a public reader
  or an AI implementing against this package. Also renamed the two custom
  `NSAttributedString.Key`s off the private repo's name (`com.richtextpoc.*` →
  `com.richtextcrossplatform.*`) while that was still a free, pre-tag change (see `v0.3.0` below —
  no tag existed yet when this landed).

## The macOS editor, built and verified — 2026-09-14

Not just scoped — built, and hands-on verified by actually launching the packaged example app on
a real Mac (typing, toolbar formatting, a real `NSTextList` bullet with correct hanging indent all
confirmed visually), not only by `swift build`/`swift test` passing. Three real bugs were found
this way that no amount of code review or compiling would have caught — see
`docs/ARCHITECTURE.md`'s new macOS section for the technical detail on each:

1. Plain `NSTextView()` defaults to legacy TextKit 1, unlike `UITextView()` — the explicit opt-in
   is `NSTextView(usingTextLayoutManager: true)`.
2. Reading the legacy `.layoutManager` property even once — including read-only, including from
   inside `intrinsicContentSize` written by direct analogy to the iOS version — silently and
   permanently downgrades that view to TextKit 1 compatibility mode. The TextKit-2-native
   replacement is `NSTextLayoutManager.usageBoundsForTextContainer`.
3. `NSViewRepresentable.updateNSView` is not guaranteed to re-run once a view actually gets a
   window if the `focused` binding's value doesn't change in between — a text view that should
   start focused could sit permanently unfocused. Fixed by grabbing first responder inside
   `NSView.viewDidMoveToWindow` instead of relying on `updateNSView` alone.

The two decisions this file previously flagged as needing to be made before writing the mac model
were both resolved as recommended: selection collapses to `selectedRanges.first` (documented in
the mac model's own doc comment, not left to read as an oversight), and `RichTextFormatBar` is
now genuinely shared — its `#if canImport(UIKit)` guard is gone, not just theoretically removable.
`NSTextViewDelegate`'s method shapes were indeed different from `UITextViewDelegate`'s, confirmed
by the compiler while writing `RichTextTextViewMac.swift`: `textDidChange`/`textViewDidChangeSelection`
take a `Notification` (read `.object as? NSTextView` if needed), not the text view directly, and
`shouldChangeTextIn` takes `replacementString: String?` (nilable, unlike UIKit's non-optional
`String`).

**Not yet done, tracked below rather than silently assumed:** a pass on real Mac hardware (this
was verified via a locally-launched, unsigned build automated through the Accessibility API, not
a human clicking around); the Liquid Glass toolbar's actual visual polish on macOS (functional
correctness was verified — the toolbar responds and reflects active state correctly — but its
*appearance* next to Notes-style iOS chrome hasn't been eyeballed side by side); paste-from-another-
Mac-app hardening (`RichTextEditorNSTextView.paste(_:)` exists and is a straight port of the iOS
sanitization logic, but wasn't exercised end-to-end with a real rich paste from Notes/Safari the
way the iOS path was during its own original hands-on pass).

## visionOS support, built and verified — 2026-09-15

Not just scoped (see the former "visionOS support" item under "Scoped, not yet built," now moved
here) — `docs/visionos.md`'s assessment held up under actual implementation, and its two
recommended changes both shipped: `.visionOS("26.0")` added to `Package.swift`'s `platforms:`
array, and `RichTextFormatBar.swift`'s two Liquid Glass call sites plus its outer
`GlassEffectContainer` wrapper branch on `#if os(visionOS)` to use `.glassBackgroundEffect(in:)`
and a plain `Group` instead (`GlassEffectContainer`/`.glassEffect(in:)` are
`@available(visionOS, unavailable)`). `RichTextCore`, `RichTextEditorModel`, and
`RichTextTextView` needed zero changes — visionOS shares UIKit with iOS, so it takes the same
`#if canImport(UIKit)` branch iOS already exercises.

The open product question `docs/visionos.md` deliberately left unresolved — minimal glass-effect
swap versus an ornament-based toolbar placement — was resolved in favor of the ornament.
`RichTextEditor.swift`'s `editor(_:_:)` now attaches the toolbar via
`.ornament(visibility: .automatic, attachmentAnchor: .scene(.bottom), contentAlignment: .center)`
on visionOS instead of `.safeAreaInset(edge: .bottom)`, matching visionOS's own idiom for a
persistent secondary control surface attached to a window rather than a bar floating inside
scrollable content. See `docs/ARCHITECTURE.md`'s new visionOS section for the technical detail.

**Verified by direct compilation against the real visionOS SDK, not assumed:**
`xcrun --sdk xrsimulator swiftc` against both changed files (and `RichTextCore`, to rule out any
indirect breakage) targeting `arm64-apple-xros26.0-simulator` typechecks clean — one pre-existing
`Sendable`-closure warning on `RichTextEditorConfiguration.toolbar`, unrelated to this change and
present on every platform, not a new one. `swift build`/`swift test` from the repo root still pass
on macOS after both source changes (83 `RichTextCore` tests + 6 macOS `RichTextEditor` tests,
green).

**A distinct visionOS sample app**, `examples/visionos-demo` (own `project.yml`,
`RichTextEditorVisionDemo.xcodeproj`, generated by XcodeGen the same way the iOS/macOS example is)
— not a copy of `examples/rich-text-editor-demo` with a platform flag changed. It demonstrates the
capability that has no real analogue on iOS/macOS: several documents open at once in independent
floating windows. A `WindowGroup` shows a document gallery; a second
`WindowGroup(for: Document.ID.self)` opens one `RichTextEditor` per document via
`openWindow(id:value:)`, all sharing one in-memory `DocumentLibrary`. `xcodegen generate` followed
by `xcodebuild build -destination 'platform=visionOS Simulator,name=Apple Vision Pro'
CODE_SIGNING_ALLOWED=NO` builds clean, and the built app was installed and launched on that
Simulator (visionOS 27.0) without crashing — the gallery window rendered correctly with its
document list. See `examples/visionos-demo/README.md`.

**Not yet done, tracked here rather than silently assumed:** any pass on real Vision Pro hardware
— everything above is Simulator-only, same caveat the macOS editor still carries for real Mac
hardware. No hands-on typing/formatting/toolbar-interaction pass was done either (the Simulator
verification above confirmed the app launches and renders, not that editing and the ornament
toolbar behave correctly under real gaze/pinch input) — the macOS editor's own hands-on pass (see
above) is the bar this hasn't cleared yet.

## The example app's Xcode project — built and verified 2026-09-14

`examples/rich-text-editor-demo` now has a real, generated `RichTextEditorDemo.xcodeproj` — not just source
files waiting on manual project creation. Built with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from a checked-in `project.yml` (`brew install xcodegen`; regenerate with `xcodegen generate` from
`examples/rich-text-editor-demo/` after editing `project.yml` or adding/removing source files) rather than a
hand-maintained `.xcodeproj`, so the project definition stays readable and diffable in version
control instead of being an opaque, merge-conflict-prone binary-ish plist.

The target is genuinely multiplatform — `platform: auto` + `supportedDestinations: [iOS, macOS]`,
matching the exact `SDKROOT = auto` / `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`
shape Apple's own "Multiplatform App" Xcode template produces — not a Mac Catalyst build and not
two separate targets. One scheme, `RichTextEditorDemo`, builds and actually ran on both
`-destination 'platform=macOS'` and a booted iOS Simulator; the `.xcodeproj` is checked in (built
artifacts under it are not — see `.gitignore`) so a consumer doesn't need XcodeGen installed just
to open and run the example, only to regenerate it after a source change.

**Real bug found 2026-09-15, by Daniel actually running this on his own iPhone — not caught by any
verification the night before, since none of it touched a real device.** `project.yml` originally
set `CODE_SIGNING_ALLOWED: false` as a workaround for building in an environment with no Apple ID
signed into Xcode at all. That setting doesn't "skip signing when there's no team" — it forces a
permanently unsigned binary regardless of what team gets selected in Xcode's Signing &
Capabilities afterward. Simulator and "My Mac" runs don't enforce code signing, so this looked
completely fine through an entire night of verification; a real device does enforce it, and
refused to install with `LaunchExecutableValidationErrorDomain` / "The executable is not
codesigned." Fixed by removing that setting entirely — `CODE_SIGN_STYLE: Automatic` with no team
hardcoded is the correct default, letting a real developer's own team selection actually take
effect. The lesson generalizes: **a signing-related setting verified only against Simulator/local-
Mac runs is not verified for real device installs** — the two paths diverge exactly here, and nothing
short of an actual device catches it. For CI (`.github/workflows/ci.yml`) and any other headless
build with no team available, `CODE_SIGNING_ALLOWED=NO` is now passed as an `xcodebuild`
command-line override instead of being baked into the shared `project.yml`.

## Packaging — verified 2026-09-14

Daniel asked whether this genuinely works as an Xcode/SPM drop-in, and which other package
managers are worth supporting. Tested directly rather than reasoned about:

- **SPM remote-dependency consumption works.** A scratch consumer package with
  `.package(url: "https://github.com/dflax/rich-text-cross-platform", branch: "main")` and both
  products as dependencies resolved and built cleanly (`swift build`, both `RichTextCore` and
  `RichTextEditor` compiled). Confirmed as an actual `swift build` against the real public URL,
  not inferred from `xcodebuild` runs against the local checkout.
- **`v0.3.0` tagged 2026-09-15 — Daniel's call, made deliberately, not a side effect of a docs
  fix.** Before this, the README's own Quick Start snippet was actually broken: `from: "0.1.0")`
  failed to resolve with no tag ever pushed (`git ls-remote --tags origin` was empty; confirmed
  directly: `error: Dependencies could not be resolved because no versions of
  'rich-text-cross-platform' match the requirement 0.1.0..<1.0.0`), so it was fixed to
  `branch: "main"` with a note to switch once a release was tagged. Not a 1.0 — the public API
  can still move — but real and working: `from: "0.3.0"` was verified against the actual pushed
  tag (a fresh scratch consumer package resolved it to revision `8fb012f`, matching the tagged
  commit exactly, and built both products cleanly). README.md and
  `docs/guides/getting-started-ios.md` now both use `from: "0.3.0"` instead of `branch: "main"`.
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

- **License: MIT** — chosen specifically because it permits commercial use without restriction,
  since a real commercial app is an intended consumer of this package. See `LICENSE`.
- **Minimum OS stays iOS 26 / macOS 26.** Not being lowered. Matches the fork point's own proven
  baseline; TextKit-2-on-`UITextView` compatibility below iOS 26 was never going to be verified
  work worth prioritizing over the macOS editor below.
- **A real macOS editor, on `NSTextView`** — not just evaluated, and no longer just committed:
  built and verified 2026-09-14, driven by a real app that needs to replace a markdown+Milkdown
  architecture that isn't working well (see `README.md`'s intro). See "The macOS editor, built and
  verified" above.

## Scoped, not yet built

Ordered by what unblocks the most other work.

1. **A web sample app** mirroring the iOS one's configuration variants
   (`configureImageBaseURL`, a demo `QuillHost` usage, a custom-toolbar-equivalent — Quill's own
   toolbar module config already *is* the "custom toolbar" story, so this is more "show it" than
   "build new capability").
2. **A build step for the web package** producing a publishable `dist/` (tsup or plain `tsc`) —
   it currently ships as source, `main`/`types` pointing straight at `src/index.ts`.
3. **Port the fork point's fuller round-trip test suite** to the web package —
   `test/round-trip.test.ts` proves byte-identity and vocabulary membership across the whole
   corpus (22 tests), which is the actual cross-platform-consistency proof, but doesn't yet cover
   every coalescing/idempotence/image-edge-case assertion `RichTextCoreTests` covers on the Swift
   side. See that package's own `README.md`.
4. **Automate keeping the two Swift-side fixture copies in sync** (repo-root `fixtures/`, used by
   the web package's tests, and `Tests/RichTextCoreTests/Resources/fixtures`, required by SPM's
   resource-bundling rules) — a script or a pre-commit check, so they can't silently drift.
5. **Hands-on verification on real hardware**, ported from the fork point's own outstanding
   items — hanging indent and non-selectable markers under live editing on a real iPhone/iPad/Mac
   (not just Simulator and an unsigned local Mac build driven by the Accessibility API — see "The
   macOS editor" above for exactly what that pass did and didn't cover), cross-editor consistency
   (well, cross-*platform* now: iOS-authored ↔ macOS-read ↔ web-read), full toolbar/list-editing
   parity. The fork point never finished this pass before extraction; it needs redoing here since
   this is a different package with a different public API surface, not the same code under a new
   name.
6. **CI** — GitHub Actions running `swift test` (cross-platform, `RichTextCore` + the macOS half of
   `RichTextEditor`), `xcodebuild test -scheme RichTextCrossPlatform-Package -destination
   'platform=iOS Simulator,…'` (the iOS half of `RichTextEditor`), and `npm test`/
   `npm run typecheck` for the web package, on every PR. Not yet set up. `examples/rich-text-editor-demo`'s own
   build (`xcodegen generate` then `xcodebuild build` for both `platform=macOS` and an iOS
   Simulator destination) is worth a CI job too, now that it's a real, generated Xcode project
   rather than loose source files.
7. **CONTRIBUTING.md, issue/PR templates.** Open-source hygiene not yet done.

## Open decisions, not yet made

- **How to distribute this once it's more than one product's worth of platforms** — today's
  single `Package.swift`/two-products shape (see "One `Package.swift` at the repo root" above)
  held up fine even through adding the macOS editor; if this ever needs to split (e.g. a
  genuinely separate release cadence per platform), that's a real decision to make deliberately,
  not a default to fall into.
- **Whether the fork point's SwiftUI/`TextEditor`-based editor is worth ever revisiting** —
  deliberately not ported (see `PROVENANCE.md`), and the calculus hasn't changed now that a real
  `NSTextView` editor exists for macOS too: it would be a second, structurally worse iOS editor
  (no real inline images, no real list markers, and the fork point's own code carries visible
  scars from an unresolved multi-round selection-tracking investigation — see
  `rich-text-poc/apple/RichTextPOC/RichTextPOC/DocumentEditorView.swift`'s `SegmentTextEditor` if
  this is ever reconsidered) for no proven benefit over what's already shipped.
- **Whether to keep XcodeGen as the example app's project-generation tool, or move to a
  hand-maintained `.xcodeproj`** once the example app's structure stabilizes — XcodeGen keeps
  `project.yml` diffable and avoids merge conflicts in a binary-ish `.xcodeproj`, at the cost of a
  build-time dependency (`brew install xcodegen`) for anyone who needs to *regenerate* it (opening
  and running the checked-in `.xcodeproj` needs nothing extra).
