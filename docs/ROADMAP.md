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
  required by SPM's resource-bundling rules) and the web package's tests are proven against.
  **A symlink was tried 2026-09-16 and reverted the same day**: it passed locally (`rm -rf .build
  && swift test`, 83 green) but failed on a genuinely fresh CI checkout — SPM's resource-copy step
  copied the symlink itself rather than dereferencing it, so the relative target
  (`../../../fixtures`) no longer pointed anywhere real once relocated inside the built test
  bundle, and every fixture lookup failed with `.notFound`. Reverted to two real copies plus an
  actual drift check instead: `.github/workflows/ci.yml`'s `swift-test` job now runs
  `diff -rq fixtures Tests/RichTextCoreTests/Resources/fixtures` before `swift test`, so the two
  can't silently diverge even though they're no longer prevented from diverging by construction.
  **Lesson for next time:** "it passed locally" is not evidence a symlinked SPM resource works —
  a local working tree already has both paths resolved on disk in a way a fresh CI checkout's
  build step does not necessarily preserve; verify a resource-bundling change against a truly
  clean checkout (or in CI itself) before trusting a local green run.
- **Postgres backend** — see `backends/postgres/`.
- **Web package** (`web/packages/rich-text-editor`) — `delta.ts`/`vocabulary.ts`/`quill-setup.ts`/
  `image-key.ts`/`QuillHost.tsx` ported from the fork point's `web/` app and genericized (no more
  B2-specific naming, a configurable image base URL instead of a hardcoded bucket). 22 tests
  green (`npm test`), including byte-identical round-trip and vocabulary-membership checks
  against the *same* fixture corpus the Swift package uses — the actual cross-platform-
  consistency proof, not just a claim. `npx tsc --noEmit` clean. **Real build step added
  2026-09-16**: `tsup` (`npm run build`) produces an ESM `dist/index.js` + `dist/index.d.ts`,
  verified by actually importing the built bundle in Node and checking every expected export is
  present, not just that `tsup` exited 0. `react`/`react-dom`/`quill` stay externalized
  peer dependencies, not bundled. `main`/`module`/`types`/`exports` all point at `dist/` now.
  Not yet published to the npm registry — see below.
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
- **`RichTextEditorConfiguration.toolbar`'s `@Sendable` fix** — the closure type is now
  `@MainActor @Sendable (RichTextEditorModel) -> AnyView`, not just `@MainActor`. Verified via
  `swift build -Xswiftc -strict-concurrency=complete` after `rm -rf .build` (zero warnings, where
  it previously warned), `swift test` (83 tests green), and rebuilding
  `examples/rich-text-editor-demo` for macOS — the one real call site that constructs this closure
  (`CustomToolbarEditorView.swift`) still compiles clean.
- **CONTRIBUTING.md, issue templates (bug report, feature request), and a PR template** — added
  2026-09-16. The PR template's checklist encodes real project-specific lessons rather than a
  generic list: verifying both sides of an `#if canImport` gate, accounting for the 1.0 API
  freeze, and keeping `docs/ROADMAP.md` updated in the same PR that makes it stale.
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

**Real hardware and hands-on verification — done, 2026-09-16.** The items below were verified
Simulator-only and via Accessibility-API automation on an unsigned local build as of 2026-09-14;
Daniel has since installed and run this on his own Mac and iOS hardware directly and confirmed:
real typing and toolbar formatting; the Liquid Glass toolbar's visual polish, eyeballed live
on-device next to iOS chrome, not just the functional correctness verified earlier; and
`RichTextEditorNSTextView.paste(_:)` against a real rich paste from both Notes and Safari on
macOS — the same two apps the iOS paste-hardening tests were originally validated against — the
agreed formatting subset is stripped and the rest preserved correctly, not just passing its own
unit-level assumptions. Still open: the same pass on real Vision Pro hardware — see "visionOS
support" below, which remains Simulator-only.

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
present on every platform, not a new one (fixed 2026-09-16 — see "Done and verified" above).
`swift build`/`swift test` from the repo root still pass
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
  Superseded 2026-09-15/16: `v0.4.0` tagged, and README.md + both `getting-started-*.md` guides
  bumped to `from: "0.4.0"` accordingly (were still stuck on `0.3.0` until 2026-09-16).
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

## Decided (2026-09-16)

- **Freezing the public API for 1.0.** Daniel's call. Nothing found in this audit blocks it:
  `web/packages/rich-text-editor` references Quill as a real npm `peerDependency` (`^2.0.2`),
  dynamically imported at runtime (`await import("quill")` in `QuillHost.tsx`) — never vendored —
  so there's no embedded-vs-referenced cleanup hiding behind the freeze. The frozen surface is
  `RichTextEditor`, `RichTextEditorModel`, `RichTextTextView`, `RichTextEditorConfiguration`,
  `RichTextImageUploading`, `ImageDownscaling`, `Delta`, `ImageStore` (Swift) and `QuillHost`,
  `configureImageBaseURL`, `Delta` (web). README.md's Contributing section still says "expect the
  public API to move" — that needs to go once the 1.0 tag actually lands, not before (see
  `BACKLOG.md`'s "Path to 1.0" section for the release-mechanics checklist this still needs:
  CHANGELOG, the tag itself, and whether the web package versions in lockstep or independently).
- **Distribution stays a single `Package.swift`, two products** — reaffirmed for 1.0. The
  "Open decisions" entry above about a future split (a genuinely separate release cadence per
  platform) remains true *if* that need ever arises, but it isn't arising now, so it isn't a
  precondition for 1.0.
- **XcodeGen stays** as the example app's project-generation tool. No hand-maintained
  `.xcodeproj` migration planned; the diffability/merge-conflict trade-off that motivated XcodeGen
  in the first place hasn't changed.
- **The SwiftUI `TextEditor`-based editor path stays unported, with a specific reopening
  condition — Daniel's call, 2026-09-16.** Not a vague "no proven benefit": the POC actually built
  and compared it (see `PROVENANCE.md`'s "What was deliberately not ported"), and it failed on a
  concrete dealbreaker — `TextEditor()` couldn't properly support lists with real list markers,
  plus other issues on top of that. **Reopen when Apple ships a `TextEditor()` update with proper
  list-marker support.** Daniel's expectation is that such an update would land cross-platform
  (iOS/macOS/visionOS at once, the way SwiftUI APIs generally do) — if and when that happens, a
  single `TextEditor()`-based implementation is *preferred* over today's two structurally
  different editors (`UITextView` on iOS/iPadOS/visionOS, `NSTextView` on macOS) sharing type
  names via `#if canImport`, not just an equally-valid alternative to it. Until then, nothing
  changes: this is a watch condition, not a task with a deadline.

## CI — green as of 2026-09-16

Wired up 2026-09-14, but every run failed — 9/9 red — until today. Root cause: `runs-on: macos-15`
booted an actual macOS 15.7.9 host against a package whose floor is macOS 26, so `xcodebuild`
couldn't find a matching destination (`doesn't support My Mac's macOS 15.7.9`) and the built
macOS test bundle `dlopen`-failed on `GlassEffectContainer`, a macOS-26-only SwiftUI symbol —
Xcode having the 26 SDK installed doesn't help when the host OS itself is 15. Fixed by moving all
three macOS jobs to the `macos-26` hosted runner image (now published by `actions/runner-images`);
there's deliberately no macOS-15 fallback. `xcode-version` is pinned to `"26.6.0"`, confirmed by
a real all-green run (all four jobs: `swift-test`, `ios-simulator`, `example-app`, `web`) —
`latest-stable` is gone, not a placeholder anymore. Also fixed in the same pass: the iOS-Simulator-
destination step's `$SIMULATOR_ID` came back empty in every earlier failed log
(`xcodebuild -destination "id="` matched nothing) — now fails fast with a clear error instead of
silently doing nothing, so a future runner-image change can't mask this again.
`examples/rich-text-editor-demo`'s own build (`xcodegen generate` then `xcodebuild build` for both
`platform=macOS` and an iOS Simulator destination) already has its own job, now that it's a real,
generated Xcode project rather than loose source files.

## Scoped, not yet built

Ordered by what unblocks the most other work.

1. **A web sample app** mirroring the iOS one's configuration variants
   (`configureImageBaseURL`, a demo `QuillHost` usage, a custom-toolbar-equivalent — Quill's own
   toolbar module config already *is* the "custom toolbar" story, so this is more "show it" than
   "build new capability").
2. **Port the fork point's fuller round-trip test suite** to the web package —
   `test/round-trip.test.ts` proves byte-identity and vocabulary membership across the whole
   corpus (22 tests), which is the actual cross-platform-consistency proof, but doesn't yet cover
   every coalescing/idempotence/image-edge-case assertion `RichTextCoreTests` covers on the Swift
   side. See that package's own `README.md`.
3. **Cross-platform round-trip consistency**: iOS-authored ↔ macOS-read ↔ web-read, and full
   toolbar/list-editing parity checked across all three, not just per-platform. (Hands-on hardware
   verification itself — hanging indent, non-selectable markers, toolbar formatting under live
   editing on a real iPhone/iPad/Mac — is done; see "Real hardware and hands-on verification"
   above. Real Vision Pro hardware is still open, same section.) The fork point never finished this
   specific cross-platform pass before extraction; it needs doing here since this is a different
   package with a different public API surface, not the same code under a new name.
