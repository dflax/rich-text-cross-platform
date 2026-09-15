# Multiplatform sample — RichTextEditorDemo

Three screens, one per `RichTextEditorConfiguration` variant, so the differences are visible
side by side instead of buried in separate app targets. The same three screens run unchanged on
iOS, iPadOS, and macOS — nothing in `RichTextEditorDemo/` is platform-gated:

- **Minimal** — a `Delta` binding and an `ImageStore`, nothing else. `allowsImages: false` hides
  the photo button for a text-only editor.
- **With image upload** — a demo `RichTextImageUploading` conformance that "uploads" by copying
  into a local cache directory, so this runs with no real backend. Swap `DemoImageUploader` for a
  real one (S3, B2, Firebase Storage, …) in your own app — see
  [`docs/guides/getting-started-ios.md`](../../docs/guides/getting-started-ios.md).
- **Custom toolbar** — replaces the default Liquid Glass toolbar entirely via
  `RichTextEditorConfiguration.toolbar`, driving the same `RichTextEditorModel` actions
  (`toggleBold`, `setLineStyle`, …) from a minimal text-button bar instead.

## Status: real, generated, and hands-on verified on both platforms

`RichTextEditorDemo.xcodeproj` is a real, checked-in Xcode project (its `project.pbxproj` is
tracked; everything else in the bundle — user state, `xcuserdata/` — is gitignored as usual). It's
generated from [`project.yml`](project.yml) by [XcodeGen](https://github.com/yonaskolb/XcodeGen)
rather than hand-maintained, so the project definition stays readable and diffable instead of an
opaque, merge-conflict-prone binary-ish plist.

**Open and run it directly — no XcodeGen needed for that:**

```
open RichTextEditorDemo.xcodeproj
```

Pick any run destination (an iOS/iPadOS Simulator, or "My Mac") and run. This has been verified
concretely, not just built: on macOS, the packaged app was launched, typed into, and formatted
through its toolbar, producing a real `NSTextList` bullet marker with correct hanging indent —
see `docs/ROADMAP.md` and `docs/ARCHITECTURE.md` for what that pass found (including three real
AppKit/TextKit-2 bugs it caught that no amount of `swift build` would have). On iOS, the app
launches on Simulator and the package's own `RichTextEditorModel` test suite passes against a
real, attached `UITextView` via `xcodebuild test -destination 'platform=iOS Simulator,…'`.

**Running on a real iPhone/iPad, not just Simulator:** select the `RichTextEditorDemo` target,
open Signing & Capabilities, and pick your own team under "Team" (a free personal-team Apple ID
is enough for a device you own — no paid Developer Program membership required). Signing is left
on `Automatic` with no team hardcoded in `project.yml`, deliberately: a real device refuses to
install an app with no code signature at all, so nothing here should ever force signing off by
default the way an earlier version of this file briefly did. If Xcode still shows a signing error
after picking a team, try Product → Clean Build Folder first — a stale unsigned build product can
linger. The first run on a fresh device may also need you to trust the developer certificate under
Settings → General → VPN & Device Management, a normal iOS step unrelated to this project.

**If you add, remove, or rename a source file, or change `project.yml`:**

```
brew install xcodegen   # once
xcodegen generate       # from this directory, regenerates RichTextEditorDemo.xcodeproj
```

The project targets `platform: auto` with `supportedDestinations: [iOS, macOS]` — Apple's own
"Multiplatform App" shape (one target, not Mac Catalyst, not two separate targets) — matching the
`RichTextEditor` package's own iOS 26 / macOS 26 minimum (see `docs/ROADMAP.md`'s Decided section:
this floor is deliberate, not being lowered).
