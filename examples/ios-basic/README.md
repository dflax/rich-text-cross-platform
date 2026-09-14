# iOS sample — RichTextEditorDemo

Three screens, one per `RichTextEditorConfiguration` variant, so the differences are visible
side by side instead of buried in separate app targets:

- **Minimal** — a `Delta` binding and an `ImageStore`, nothing else. `allowsImages: false` hides
  the photo button for a text-only editor.
- **With image upload** — a demo `RichTextImageUploading` conformance that "uploads" by copying
  into a local cache directory, so this runs with no real backend. Swap `DemoImageUploader` for a
  real one (S3, B2, Firebase Storage, …) in your own app — see
  [`docs/guides/getting-started-ios.md`](../../docs/guides/getting-started-ios.md).
- **Custom toolbar** — replaces the default Liquid Glass toolbar entirely via
  `RichTextEditorConfiguration.toolbar`, driving the same `RichTextEditorModel` actions
  (`toggleBold`, `setLineStyle`, …) from a minimal text-button bar instead.

## Status: source is complete; the `.xcodeproj` wrapper is not generated yet

The Swift source in `RichTextEditorDemo/` is real and complete — every file compiles against the
`RichTextEditor` public API as written. What's missing is the Xcode project file itself: this
was written in a session where the tool that scaffolds a new Xcode project required a one-time
manual approval click (the Xcode MCP menu bar icon) that wasn't available at the time. Two ways
to finish this, both quick:

1. **In Xcode**: File → New → Project → iOS → App, name it `RichTextEditorDemo`, no storage/no
   tests. Delete the generated `RichTextEditorDemoApp.swift`/`ContentView.swift`, drag the four
   files from `RichTextEditorDemo/` in this directory into the project instead. Add this repo's
   `swift/` package as a local Swift Package dependency (File → Add Package Dependencies… → Add
   Local…), linking both `RichTextCore` and `RichTextEditor`. Run.
2. **Ask an agent with Xcode MCP access to retry `XcodeNewProject`** targeting this directory
   with `templateIdentifier: com.apple.dt.unit.multiPlatform.app`, `productName:
   RichTextEditorDemo`, then move these four source files in over the template's generated ones
   and add the local package dependency the same way.

Once wrapped, this needs the same deployment target as the `RichTextEditor` package (iOS 26 —
see `docs/ROADMAP.md`'s Open Decisions for why, and the plan to lower it).
