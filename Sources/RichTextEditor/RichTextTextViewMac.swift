#if canImport(AppKit)
import AppKit
import RichTextCore
import SwiftUI
import UniformTypeIdentifiers

/// An `NSTextView` that reports its own fitting height as its intrinsic content size, so the
/// representable never needs a separate SwiftUI height binding kept in sync by hand — the AppKit
/// counterpart of `RichTextEditorUITextView`'s `intrinsicContentSize` override. `NSTextView` has
/// no `isScrollEnabled` — the auto-growing-height trick here is instead: track the view's own
/// width in the text container, give the container unbounded height, and derive
/// `intrinsicContentSize` from the layout manager's used rect (see `docs/ROADMAP.md`).
final class RichTextEditorNSTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        // Real bug found by actually launching this editor: touching the legacy `.layoutManager`
        // property at all — even just to read it — makes AppKit transparently create a
        // compatibility `NSLayoutManager` and permanently fall back to TextKit 1 for this view,
        // silently, no error. `NSTextLayoutManager.usageBoundsForTextContainer` is the TextKit-2
        // -native equivalent of `NSLayoutManager.usedRect(for:)` and must be used instead.
        guard let textLayoutManager else { return super.intrinsicContentSize }
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        let height = textLayoutManager.usageBoundsForTextContainer.height
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(height))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }

    /// TextKit 2 is asserted, not assumed. Checked once this view actually has a window, not
    /// synchronously after `makeNSView` — a real bug found by actually launching this editor:
    /// checking any earlier (even on a `DispatchQueue.main.async` hop) still fired the assertion
    /// every time, since `textLayoutManager` isn't reliably established until AppKit has really
    /// attached this view to its hosting window. Mirrors `RichTextEditorUITextView`'s own
    /// `didMoveToWindow` override, which checks a different thing (dynamic color resolution) for
    /// the same underlying reason — window attachment is the first point some AppKit/UIKit state
    /// is guaranteed accurate.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        assert(textLayoutManager != nil, "NSTextView fell back to TextKit 1 — list markers and hanging indent will not render correctly.")
        // Real bug found by actually launching this editor: `updateNSView`'s reactive
        // first-responder sync (below) is not a reliable enough trigger on its own — SwiftUI does
        // not always re-run `updateNSView` again once this view actually has a window if nothing
        // else changes the `focused` binding's value in between, so a text view that should start
        // focused (the default for this editor, matching iOS) could sit unfocused indefinitely.
        // Grabbing first responder here, once attachment is real, closes that gap; if a host
        // explicitly wants `focused == false`, `updateNSView`'s own sync resigns it right after.
        if window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
    }

    // MARK: - Vocabulary enforcement: close off the system's own Format menu / Font panel

    /// AppKit has no single `allowsEditingTextAttributes` switch the way `UITextView` does — the
    /// Format menu's font/color/alignment items arrive here as responder-chain action methods.
    /// `usesFontPanel = false` (set by the representable) stops the Font panel from targeting
    /// this view; overriding the action methods themselves as no-ops is the belt-and-suspenders
    /// second layer, matching this editor's existing two-layer posture elsewhere (see
    /// `docs/guides/vocabulary-enforcement.md`). Every attribute this editor ever writes comes
    /// from its own toolbar.
    override func changeFont(_ sender: Any?) {}
    override func changeColor(_ sender: Any?) {}
    override func changeAttributes(_ sender: Any?) {}

    /// The primary control against a disallowed attribute reaching the buffer: pasted content is
    /// the realistic vector (arbitrary font, color, point size, a foreign paragraph style/list
    /// riding along from another app), since the toolbar itself only ever writes vocabulary
    /// attributes. Reads the pasteboard's rich representations directly, sanitizes with
    /// `NSDeltaCodec.sanitizedForPaste`, and inserts that instead of whatever `super.paste(_:)`
    /// would otherwise do. A plain-text-only pasteboard falls through to `super.paste(_:)` —
    /// plain text only ever picks up `typingAttributes`, which are already vocabulary-only.
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        var raw: NSAttributedString?
        // HTML first, RTF as a fallback — see `RichTextEditorUITextView.paste(_:)`'s own doc
        // comment for why HTML wins when both are offered.
        if let html = pasteboard.data(forType: .html) {
            raw = try? NSAttributedString(
                data: html,
                options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
            )
        }
        if raw == nil, let rtf = pasteboard.data(forType: .rtf) {
            raw = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        }
        guard let raw, raw.length > 0 else {
            super.paste(sender)
            return
        }

        let sanitized = NSDeltaCodec.sanitizedForPaste(raw)
        guard sanitized.length > 0, let storage = textStorage else { return }

        let range = selectedRanges.first?.rangeValue ?? NSRange(location: 0, length: 0)
        // Same inline-image-adjacency guard ordinary typing goes through — see
        // `RichTextEditorUITextView.paste(_:)`'s own doc comment for the same trade-off.
        guard delegate?.textView?(self, shouldChangeTextIn: range, replacementString: sanitized.string) ?? true else { return }

        storage.beginEditing()
        storage.replaceCharacters(in: range, with: sanitized)
        storage.endEditing()
        selectedRanges = [NSValue(range: NSRange(location: range.location + sanitized.length, length: 0))]
        didChangeText()
    }
}

/// Wraps a single, continuous `NSTextView` over the whole document — the macOS counterpart of
/// `RichTextTextView` (declared under `#if canImport(UIKit)` in `RichTextTextView.swift`). Same
/// public type name on both platforms, implemented in mutually-exclusive files.
///
/// Two rules this type exists to satisfy, same as the iOS side:
/// - **`updateNSView` never replaces the text view's content wholesale.** `model` holds no
///   separate copy of the text — `updateNSView` only ever syncs focus state.
/// - **TextKit 2 is asserted, not assumed.**
struct RichTextTextView: NSViewRepresentable {
    let model: RichTextEditorModel
    let initialContent: NSAttributedString
    @Binding var focused: Bool

    func makeNSView(context: Context) -> RichTextEditorNSTextView {
        // Real bug found by actually launching this editor (not caught by `swift build`, which
        // can't exercise a live text view): the plain `NSTextView()` convenience initializer
        // defaults to legacy TextKit 1 on AppKit — unlike `UITextView()`, which defaults to
        // TextKit 2. `init(usingTextLayoutManager:)` is the explicit opt-in AppKit needs.
        let view = RichTextEditorNSTextView(usingTextLayoutManager: true)
        view.delegate = context.coordinator
        // Belt-and-suspenders alongside `NSDeltaCodec.decode` always setting an explicit
        // `.foregroundColor`, matching the iOS representable's own rationale.
        view.textColor = .labelColor
        view.font = .preferredFont(forTextStyle: .body)
        view.typingAttributes = [.font: PlatformFont.preferredFont(forTextStyle: .body), .foregroundColor: PlatformColor.labelColor]
        view.isEditable = true
        view.isSelectable = true
        view.isRichText = true
        view.allowsUndo = true
        // The single most important correctness control on this side: the system's own Format
        // menu / Font panel must never be able to write an attribute outside the vocabulary.
        // Every attribute this editor ever applies comes from its own toolbar.
        view.usesFontPanel = false
        view.textContainerInset = NSSize(width: 4, height: 8)
        view.drawsBackground = false

        // No enclosing NSScrollView: this view grows to fit its content within the outer SwiftUI
        // ScrollView, the same "isScrollEnabled = false" shape the iOS editor uses — see
        // `RichTextEditorNSTextView`'s own doc comment.
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        view.textStorage?.setAttributedString(initialContent)
        model.attach(view)
        return view
    }

    func updateNSView(_ nsView: RichTextEditorNSTextView, context: Context) {
        let isFirstResponder = nsView.window?.firstResponder === nsView
        if focused, !isFirstResponder {
            nsView.window?.makeFirstResponder(nsView)
        } else if !focused, isFirstResponder {
            nsView.window?.makeFirstResponder(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, focused: $focused)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: RichTextEditorModel
        var focused: Binding<Bool>

        init(model: RichTextEditorModel, focused: Binding<Bool>) {
            self.model = model
            self.focused = focused
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            model.shouldChangeText(in: range, replacementText: replacementString ?? "")
        }

        func textDidChange(_ notification: Notification) {
            model.selectionChanged()
            // Mirrors the iOS coordinator's ~1s idle debounce, driven by `markDirty()`.
            model.markDirty()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            model.selectionChanged()
        }

        func textDidBeginEditing(_ notification: Notification) {
            if !focused.wrappedValue { focused.wrappedValue = true }
        }

        func textDidEndEditing(_ notification: Notification) {
            if focused.wrappedValue { focused.wrappedValue = false }
        }
    }
}
#endif
