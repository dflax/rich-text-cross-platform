#if canImport(UIKit)
import RichTextCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A `UITextView` that reports its own fitting height as its intrinsic content size, so the
/// representable never needs a separate SwiftUI height binding kept in sync by hand — including
/// after a *programmatic* mutation (insert image, toggle a list) that never passes through the
/// delegate callbacks a binding-based approach would depend on.
final class RichTextEditorUITextView: UITextView {
    #if os(iOS)
    private var accessoryHostingController: UIHostingController<AnyView>?

    /// Pins the format toolbar directly to the keyboard via `UITextView.inputAccessoryView` —
    /// hierarchy-independent, unlike the `.safeAreaInset`-based toolbar this replaced (still used
    /// on macOS/visionOS), which depends on this text view's enclosing ScrollView/Form/sheet
    /// structure to size and position it correctly. Real hands-on device testing found the
    /// `.safeAreaInset` toolbar stayed pinned to the bottom of the (auto-growing) text view
    /// instead of the keyboard on a long document; two separate attempts at fixing that by moving
    /// `RichTextEditor` into its own full-screen `.sheet` both broke on an unrelated SwiftUI bug
    /// (a `.sheet` nested inside another sheet's own `NavigationStack` collapsing the whole
    /// presentation). `inputAccessoryView` sidesteps that entire class of problem: it's positioned
    /// by UIKit against the keyboard itself, regardless of what SwiftUI container this text view
    /// happens to live inside.
    func setAccessoryContent(_ content: AnyView) {
        if let accessoryHostingController {
            accessoryHostingController.rootView = content
            return
        }
        let hosting = UIHostingController(rootView: content)
        hosting.view.backgroundColor = .clear
        hosting.safeAreaRegions = []
        // Lets the accessory view's height track the SwiftUI content's own ideal size — it
        // changes whenever the "Aa" panel opens/closes — instead of a fixed frame set once here.
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        accessoryHostingController = hosting
        if isFirstResponder { reloadInputViews() }
    }

    override var inputAccessoryView: UIView? {
        get { accessoryHostingController?.view }
        set { /* no-op: content is driven exclusively via setAccessoryContent(_:) */ }
    }
    #endif

    override var intrinsicContentSize: CGSize {
        // Before the first real layout pass `bounds.width` is 0; a generous placeholder width
        // is fine since `layoutSubviews` invalidates this again as soon as a real width lands.
        let width = bounds.width > 0 ? bounds.width : 1000
        let fitting = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(fitting.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }

    /// Fixes a real, hands-on-confirmed bug: the *first* `UITextView` ever bridged into this
    /// SwiftUI hierarchy in a given app session rendered its dynamic `.label` text color wrong
    /// (indistinguishable from invisible in Dark Mode) — but only the first one; a second
    /// editor session for the same document, later in the same run, rendered correctly. The
    /// distinguishing fact is timing: `makeUIView` runs, and `attributedText` is assigned,
    /// *before* this view has an actual window — `UIColor.label` can resolve against a
    /// stale/default trait collection at that point, since the real one only propagates once a
    /// view is genuinely attached to a window. A later editor session doesn't hit this because
    /// window/trait propagation for this hierarchy is by then already established. Re-applying
    /// the dynamic color once a real window exists — the one point `traitCollection` is
    /// guaranteed accurate — forces a fresh, correct resolution regardless of what happened at
    /// `makeUIView` time.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, textStorage.length > 0 else { return }
        textColor = .label
        let full = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            guard value is UIColor else { return }
            textStorage.addAttribute(.foregroundColor, value: UIColor.label, range: range)
        }
        textStorage.endEditing()
    }

    /// The primary control against a disallowed attribute reaching the buffer: pasted content is
    /// the realistic vector (arbitrary font, color, point size, a foreign
    /// paragraph style/list riding along from Notes or Safari) to reach the buffer, since the
    /// toolbar itself only ever writes vocabulary attributes. Reads the pasteboard's rich
    /// representations directly, sanitizes with `NSDeltaCodec.sanitizedForPaste`, and inserts
    /// that instead of whatever `super.paste(_:)` would otherwise do. A plain-text-only
    /// pasteboard (no RTF/HTML representation) falls through to `super.paste(_:)` — plain text
    /// only ever picks up `typingAttributes`, which are already vocabulary-only, so there is
    /// nothing to sanitize there.
    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        var raw: NSAttributedString?
        // HTML first, RTF as a fallback — a real bug found by hands-on testing: a link copied
        // from Notes (whose pasteboard offers RTF) was silently dropped, while the identical
        // case from Safari (HTML) survived. iOS's RTF-to-NSAttributedString importer doesn't
        // reliably preserve RTF's hyperlink field construct (`\field...HYPERLINK`) as a `.link`
        // attribute; its HTML importer maps `<a href>` correctly. Preferring HTML avoids losing
        // an in-vocabulary attribute purely because of which import path happened to run first.
        if let html = pasteboard.data(forPasteboardType: UTType.html.identifier) {
            raw = try? NSAttributedString(
                data: html,
                options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
            )
        }
        if raw == nil, let rtf = pasteboard.data(forPasteboardType: UTType.rtf.identifier) {
            raw = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        }
        guard let raw, raw.length > 0 else {
            super.paste(sender)
            return
        }

        let sanitized = NSDeltaCodec.sanitizedForPaste(raw)
        guard sanitized.length > 0 else { return }

        let range = selectedRange
        // Same inline-image-adjacency guard ordinary typing goes through — a paste landing
        // directly next to an attachment is redirected onto its own line rather than merging
        // onto the image's line. That redirect inserts plain text; a paste at exactly this
        // boundary is a rare enough edge case that degrading to plain text there, rather than
        // duplicating the redirect's own line-splitting logic for rich content, is an acceptable
        // trade against real structural safety.
        guard delegate?.textView?(self, shouldChangeTextIn: range, replacementText: sanitized.string) ?? true else { return }

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: range, with: sanitized)
        textStorage.endEditing()
        selectedRange = NSRange(location: range.location + sanitized.length, length: 0)
        delegate?.textViewDidChange?(self)
    }
}

/// Wraps a single, continuous `UITextView` over the whole document — not a stack of
/// per-segment editors — since inline `NSTextAttachment` images give every line, including one
/// carrying an image, a normal place in one text storage.
///
/// Two rules this type exists to satisfy:
/// - **`updateUIView` never does `uiView.attributedText = newValue`.** There is no `newValue` —
///   `model` holds no separate copy of the text (see `RichTextEditorModel`'s own doc comment) —
///   so the hazard this rule guards against (resetting selection/scroll on every SwiftUI update
///   pass) structurally cannot occur here.
/// - **TextKit 2 is asserted, not assumed.** `UITextView` silently falls back to TextKit 1 the
///   moment anything touches its legacy `layoutManager` property, with no error — just wrong
///   rendering (no real hanging indent, no true non-selectable list markers). Checked once the
///   view is fully configured, not in `makeUIView` before anything has touched it.
struct RichTextTextView: UIViewRepresentable {
    let model: RichTextEditorModel
    let initialContent: NSAttributedString
    @Binding var focused: Bool
    /// iOS only: SwiftUI content pinned above the keyboard via `RichTextEditorUITextView`'s
    /// `inputAccessoryView` override. Ignored on visionOS (compiled from this same file, since
    /// visionOS `canImport(UIKit)` too), which keeps its own `.ornament`-based toolbar placement —
    /// see `RichTextEditor.swift`'s platform branching. Defaulted so a visionOS call site doesn't
    /// need to pass one.
    var accessoryToolbar: AnyView = AnyView(EmptyView())

    func makeUIView(context: Context) -> RichTextEditorUITextView {
        let view = RichTextEditorUITextView()
        view.delegate = context.coordinator
        // Belt-and-suspenders alongside `NSDeltaCodec.decode` always setting an explicit
        // `.foregroundColor`: a `textColor`/baseline `typingAttributes` here means text typed
        // where nothing existing is available to inherit from (an empty document) is never left
        // to whatever a bare `NSAttributedString` defaults to — the exact dark-mode
        // invisible-text bug hands-on testing found in the real editor.
        view.textColor = .label
        view.font = .preferredFont(forTextStyle: .body)
        view.typingAttributes = [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor.label]
        view.attributedText = initialContent
        view.isEditable = true
        view.isSelectable = true
        // The single most important correctness control on this side: the system's own format
        // UI (the iOS selection menu's font/color controls) must never be able to write an
        // attribute outside the vocabulary. Every attribute this editor ever applies comes from
        // its own toolbar.
        view.allowsEditingTextAttributes = false
        // The selection callout's "Proofread | Rewrite" entry is iOS's own Writing Tools
        // integration, offered automatically to every editable text view — not something this
        // app opted into. `.none` is the documented way to opt back out; Writing Tools rewrites
        // by replacing whole runs of attributed text, which is exactly the kind of write this
        // vocabulary can't verify came from this app's own toolbar.
        view.writingToolsBehavior = .none
        view.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        view.backgroundColor = .clear
        // Without this, UITextView scrolls internally and refuses to grow to fit its content.
        view.isScrollEnabled = false
        view.setContentHuggingPriority(.required, for: .vertical)

        model.attach(view)
        #if os(iOS)
        view.setAccessoryContent(accessoryToolbar)
        #endif

        DispatchQueue.main.async {
            assert(view.textLayoutManager != nil, "UITextView fell back to TextKit 1 — list markers and hanging indent will not render correctly.")
        }
        return view
    }

    func updateUIView(_ uiView: RichTextEditorUITextView, context: Context) {
        #if os(iOS)
        uiView.setAccessoryContent(accessoryToolbar)
        #endif
        if focused, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !focused, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, focused: $focused)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        let model: RichTextEditorModel
        var focused: Binding<Bool>

        init(model: RichTextEditorModel, focused: Binding<Bool>) {
            self.model = model
            self.focused = focused
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            model.shouldChangeText(in: range, replacementText: text)
        }

        func textViewDidChange(_ textView: UITextView) {
            model.selectionChanged()
            // Mirrors `EditorModel`'s ~1s idle debounce.
            model.markDirty()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            model.selectionChanged()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !focused.wrappedValue { focused.wrappedValue = true }
        }

        /// Without this override, `UITextView`'s default behavior activates a `.link` attribute
        /// on a single tap even while `isEditable == true` — confirmed by real hands-on device
        /// testing, not assumed: tapping into linked text opened the URL instead of placing a
        /// cursor there, making a link's own text impossible to select or edit by tapping (the
        /// only workaround was iOS's keyboard-trackpad cursor-drag gesture). `.invokeDefaultAction`
        /// is what a plain tap sends; returning `false` for it makes tapping linked text behave
        /// like tapping any other text — cursor placement, nothing more — matching Notes.app and
        /// Mail's own editable-link behavior. `.presentActions` (long-press) still returns `true`,
        /// so the system's own Open/Copy Link menu remains available; a link stays fully usable,
        /// just not by accident on a single tap.
        func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            interaction == .presentActions
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if focused.wrappedValue { focused.wrappedValue = false }
        }
    }
}
#endif
