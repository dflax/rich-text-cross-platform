# visionOS support — assessment and recommendation

**Recommendation: add it.** The gap is small, well-understood, and verified directly against the
real visionOS 27.0 SDK on 2026-09-14 (`xcrun --sdk xrsimulator swiftc -target
arm64-apple-xros27.0-simulator`, compiling this repo's actual source files, not a guess from
documentation) — not scoped from first principles. This is not a structural port like the macOS
editor was; visionOS shares UIKit with iOS, so the editing logic needs no rewrite at all.

## What already works, unmodified — verified by direct compilation

- **`RichTextCore`** (`Delta`, `NSDeltaCodec`, `Vocabulary`, `ImageStore`, `Reconciliation`, …)
  type-checks against the visionOS SDK with zero changes. It already builds on both
  `#if canImport(UIKit)` and `#elseif canImport(AppKit)`; visionOS takes the UIKit branch, the
  same one iOS already exercises.
- **`RichTextEditorModel` and `RichTextTextView`** (the real editing logic, backed by
  `UITextView`) type-check against the visionOS SDK with zero changes. `UITextView` and
  `textLayoutManager` (TextKit 2) both exist and resolve normally under
  `import UIKit` on visionOS — confirmed with a standalone compile, not inferred from "visionOS is
  UIKit-based" as an assumption. visionOS's "designed for iPad"-style native app model hosts
  `UIViewRepresentable`-wrapped `UITextView` the same way iPadOS does.
- **`RichTextEditor`** (the public SwiftUI entry point: `PhotosPicker`, `Form`, `NavigationStack`,
  `.sheet`, alerts) type-checks against the visionOS SDK with zero changes.

## What's blocked, and exactly why

**`RichTextFormatBar`'s default toolbar — the only thing that doesn't compile.** Its three Liquid
Glass call sites —

```swift
GlassEffectContainer(spacing: 16) { … }
.glassEffect(in: Capsule())
.glassEffect(in: RoundedRectangle(cornerRadius: 20))
```

— fail with `'GlassEffectContainer' is unavailable in visionOS` / `'glassEffect(_:in:)' is
unavailable in visionOS`. This isn't an oversight in this codebase: the SwiftUI declarations
themselves carry `@available(visionOS, unavailable)`. It makes sense once you know why — visionOS
has its own native, real materials system built into the compositor rather than needing an
explicit "Liquid Glass" opt-in the way iOS/macOS 26 do, and Apple's own answer for it is a
*different* API, not the absence of one.

## The real, idiomatic fix — also verified by direct compilation, not guessed

visionOS's own equivalent is `.glassBackgroundEffect(in:)`. Swapping the two `.glassEffect(in:)`
call sites for `.glassBackgroundEffect(in:)` and replacing the `GlassEffectContainer` wrapper with
a plain `Group` compiles clean against the visionOS SDK with no other changes anywhere in
`RichTextEditor` — confirmed directly, the same way the gap above was. This is a small,
platform-conditional change to one file (`RichTextFormatBar.swift`), not a redesign:

```swift
#if os(visionOS)
Group {
    // same body, `.glassBackgroundEffect(in:)` instead of `.glassEffect(in:)`,
    // no GlassEffectContainer wrapper
}
#else
GlassEffectContainer(spacing: 16) { … }
#endif
```

## What this does *not* resolve — a real design question, not portability plumbing

Compiling and rendering *something* on visionOS is not the same question as whether a Notes-style
floating toolbar docked above the keyboard is the right interaction for a hand/eye-tracking-driven
spatial interface at all. visionOS's own idiom for exactly this kind of persistent, secondary
control surface is an **ornament** (`.ornament(attachmentAnchor:contentAlignment:ornament:)`),
attached to an edge of the window rather than floating inside the content `ScrollView` the way
this toolbar does today via `.safeAreaInset(edge: .bottom)`. Whether to:

1. Ship the minimal `.glassBackgroundEffect` swap above and call visionOS support "works,
   unstyled for the platform," or
2. Invest in an ornament-based toolbar placement specifically for visionOS (a real, if small,
   design piece — not just an API substitution)

is a product decision, not a technical one, and shouldn't be made silently as a side effect of
"making it compile." Recorded here rather than resolved so it isn't lost.

## What it would take, end to end

1. Add `.visionOS("26.0")` to `Package.swift`'s `platforms:` array, matching the existing iOS 26 /
   macOS 26 floor (visionOS 26 is the concurrent OS-version-family release — see Apple's own
   version alignment across platforms that year).
2. The `#if os(visionOS)` toolbar branch above in `RichTextFormatBar.swift` — the *only* source
   change this assessment found necessary. Decide the ornament question above before or after
   shipping the minimal version, per the product-decision note.
3. The same hands-on verification pass macOS just got (see `docs/ROADMAP.md`): launch the example
   app on the visionOS Simulator (already installed and available in this environment —
   `xcrun simctl list devices available` shows a visionOS 27.0 "Apple Vision Pro" device), type
   into it, exercise the toolbar. Real Vision Pro hardware is a deliberate non-goal for this
   project (Daniel's call, 2026-09-16 — no Vision Pro hardware access, and none planned), not a
   "not yet done" gap the way it briefly was recorded here — see `docs/ROADMAP.md`'s Decided
   section.
4. Update `README.md`'s Scope section and `docs/ARCHITECTURE.md` once real, matching the pattern
   already followed for macOS — don't leave a stale "iOS, iPadOS, macOS" framing once this lands.

## Effort relative to the macOS editor

Meaningfully smaller. The macOS editor needed a second, from-scratch `NSTextView`-backed
implementation because AppKit and UIKit are genuinely different text-editing APIs. visionOS needs
none of that — it *is* UIKit — so this is closer to "one file's toolbar chrome" than "a second
platform's editor."
