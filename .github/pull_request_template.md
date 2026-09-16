## What does this change, and why

<!-- The why matters more than the what here — see CONTRIBUTING.md. -->

## Platforms affected

<!-- iOS / iPadOS / macOS / visionOS / web — which did you actually verify, not just which
     the change touches. -->

## Checklist

- [ ] `swift test` passes (RichTextCore + macOS `RichTextEditor`), if Swift code changed
- [ ] iOS Simulator suite passes (`xcodebuild test -scheme RichTextCrossPlatform-Package
      -destination 'platform=iOS Simulator,…'`), if iOS-gated code changed
- [ ] `npm test && npx tsc --noEmit` pass in `web/packages/rich-text-editor`, if web code changed
- [ ] If this touches `#if canImport(UIKit)` / `#if canImport(AppKit)` gated files, both platforms
      were actually built, not just the one you're working on
- [ ] If this changes a public type's shape (Swift or web), it's accounted for against the 1.0 API
      freeze — see `docs/ROADMAP.md`'s Decided section
- [ ] If this adds to the formatting vocabulary, there's a linked issue discussing the design
      first (see `docs/ARCHITECTURE.md`'s Vocabulary section)
- [ ] `docs/ROADMAP.md` updated in this same PR if this makes it stale, not left as a follow-up
