# Roadmap

What's real, what's scoped but not built, and what's an open decision — written the night this
project was extracted, so the gap between "designed" and "shipped" stays honest as work
continues. Update this as items move between sections; don't let it silently go stale.

## Done and verified

- **`RichTextCore`** — ported from the fork point unchanged in logic (see `PROVENANCE.md`).
  87 tests green (83 `RichTextCoreTests` + 4 `RichTextEditorTests`), verified via
  `xcodebuild test -scheme RichTextCrossPlatform-Package -destination 'platform=iOS Simulator,…'`.
- **`RichTextEditor`** — extracted and decoupled from the fork point's backend-specific plumbing.
  Public API: `RichTextEditor` (SwiftUI view), `RichTextEditorConfiguration`,
  `RichTextImageUploading`, `ImageDownscaling`. Builds and its (small, new) test suite passes on
  iOS Simulator.
- **Fixture corpus** — moved into a proper SPM resource bundle rather than a repo-root-relative
  path, so the package doesn't assume anything about a consumer's checkout layout.
- **Postgres backend** — see `backends/postgres/`.

## Scoped, not yet built

Ordered by what unblocks the most other work.

1. **iOS sample app(s) demonstrating `RichTextEditorConfiguration` variants** — a minimal
   "just edit text locally" app, then a second configuration showing image upload wired to a
   real (or mock) `RichTextImageUploading`, and a third showing a custom toolbar via
   `configuration.toolbar`. This is the fastest way to find API rough edges before external
   users do. See `examples/`.
2. **Web package** (`web/packages/rich-text-editor`) — a Quill 2.x wrapper enforcing the same
   vocabulary this Swift package enforces, reading/writing the same `Delta` JSON. The fork
   point's `web/` app has a working Quill setup with constrained toolbar + custom image upload
   handling to port from; it has not been touched in this extraction yet. Needs its own
   vocabulary-enforcement story (Quill's own format/toolbar restriction APIs, not
   `NSTextStorageDelegate` — different platform, same requirement) and its own round-trip tests
   against the *same* fixture corpus this package uses, so both platforms are proven against
   identical bytes (see `docs/ARCHITECTURE.md`'s "one document, one mutable copy" reasoning —
   the cross-platform-consistency claim only means something if both sides use the same corpus).
3. **`docs/backends/mysql.md`, `mongodb.md`, `firebase.md`** — written guidance mapping the same
   storage contract (`docs/backends/README.md`) onto each store. Deliberately guidance, not
   shipped adapter code — see that doc for why.
4. **Web sample app** mirroring the iOS one's configuration variants, once the web package exists.
5. **U1/U2/U6/U7-equivalent hands-on verification on real hardware**, ported from the fork
   point's own outstanding items — hanging indent and non-selectable markers under live editing,
   cross-editor consistency (well, cross-*platform* now: iOS-authored ↔ web-read once the web
   package exists), full toolbar/list-editing parity. The fork point never finished this pass
   before extraction (see that repo's own `TASK-034`); it needs redoing here since this is a
   different package with a different public API surface, not the same code under a new name.
6. **CI** — GitHub Actions running `swift test` for `RichTextCore` and
   `xcodebuild test -scheme RichTextCrossPlatform-Package -destination 'platform=iOS Simulator,…'`
   for the full suite, on every PR. Not yet set up.
7. **CONTRIBUTING.md, issue/PR templates, a real `LICENSE`** — open-source hygiene not yet done;
   see README.md's License section for the one open decision (MIT vs. something else) blocking
   the last of these.

## Open decisions, not yet made

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
