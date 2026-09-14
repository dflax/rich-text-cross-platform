# Saving reliably

`RichTextEditor` writes into your `Binding<Delta>` on an idle debounce (~1s after the last
keystroke), on `onDisappear`, and on a scene-phase change. For the common case — a sheet or a
navigation push you dismiss with your own button — that's not quite enough on its own, and this
is worth understanding rather than discovering as a rare, hard-to-reproduce content-loss report.

## The race, precisely

Say your host provides its own "Done" button, outside `RichTextEditor`, that flips some
`isEditing` state to swap this view out for a read view. That state flip and this view's removal
from the hierarchy happen together. `RichTextEditorModel` holds only a `weak var textView` —
nothing else keeps the underlying `UITextView` alive — so a save racing the outgoing view's
teardown can find `textView` already `nil` and silently encode nothing, dropping whatever edit
never got a full second to debounce first.

This is not hypothetical — it's a real bug found during this project's own development, on the
exact "custom Done button" shape described above.

## The fix: let `RichTextEditor` own Done

```swift
RichTextEditor(delta: $delta, imageStore: imageStore, onDone: { isEditing = false })
```

When `onDone` is provided, a "Done" button appears in this view's own toolbar and calls `save()`
*synchronously*, while the view is still guaranteed live, before invoking your closure. This
closes the race for the common case — your `isEditing = false` (or whatever your own dismissal
logic is) only runs after the save has already happened.

## If you can't do that

Maybe your own chrome needs to own the button (a custom nav bar, a design system's own button
component). In that case, provide `onDone: nil` and instead:

- Give the debounce a real chance: don't dismiss immediately after the user's last keystroke.
- Or, better, don't rely on timing at all — read `delta.wrappedValue`'s current value (it's kept
  up to date on every debounce fire, not just at dismissal) and persist that directly from your
  own dismissal action, rather than trusting a save to complete concurrently with teardown.

`onDisappear`/scene-phase remain as a backstop regardless — for backgrounding and swipe-back
gestures your own dismissal button never sees — but treat them as a safety net, not the primary
mechanism, for a path you control yourself.
