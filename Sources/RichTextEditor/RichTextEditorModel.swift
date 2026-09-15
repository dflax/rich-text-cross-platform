#if canImport(UIKit)
import Foundation
import Observation
import RichTextCore
import UIKit

/// State for one editing session.
///
/// The one architectural choice that matters: there is no separate `document` copy this model
/// keeps in sync with the live `UITextView`. `UITextView.textStorage` **is** the document while
/// editing is happening; this model holds a weak reference to the text view and reads/writes
/// through it directly. Two independent copies of the same mutable text is exactly the shape of
/// bug that plagues SwiftUI's `TextEditor(text:selection:)` — replacing its bound value on every
/// change can silently reset selection and scroll position, even when the replacement is
/// logically identical to what was already there. Keeping exactly one mutable copy, and mutating
/// it in place through `NSTextStorage`'s own methods, removes the whole class of bug rather than
/// being careful around it. See `docs/ARCHITECTURE.md`.
@MainActor
@Observable
public final class RichTextEditorModel {

    public enum LineStyle: Equatable {
        case body, header1, header2, bullet, ordered
    }

    public private(set) var originalDelta: Delta
    public private(set) var savedDelta: Delta
    public private(set) var isDirty = false
    public private(set) var lastError: String?
    public private(set) var integrityFailure: String?

    /// Mirrors `textView.selectedRange`, updated by the coordinator's
    /// `textViewDidChangeSelection`. A plain stored value (not read live from the text view) so
    /// SwiftUI's `@Observable` tracking actually fires when the toolbar needs to re-render its
    /// active-state highlighting.
    public private(set) var selectedRange = NSRange(location: 0, length: 0)

    weak var textView: UITextView?

    /// The vocabulary-enforcement backstop — `NSTextStorage.delegate` is a weak/unowned
    /// reference, so this model is what keeps it alive for as long as the text view is attached.
    /// Paste interception (`RichTextEditorUITextView.paste(_:)`) is the primary control; this
    /// clamps anything that slips past it.
    private let vocabularyGuard = VocabularyTextStorageDelegate()

    private var debounceTask: Task<Void, Never>?

    private init(delta: Delta) {
        originalDelta = delta
        savedDelta = delta
    }

    // MARK: - Loading

    /// Decodes `delta` into an `NSAttributedString`, pre-resolving every image synchronously
    /// from the (already-warmed) `ImageStore` cache first — `NSDeltaCodec.decode` never touches
    /// the network or the actor itself. Call `imageStore.prefetch(keys:)` before this if the
    /// images aren't already cached, so decode never has to wait on one.
    public static func load(delta: Delta, imageStore: ImageStore) async -> (RichTextEditorModel, NSAttributedString) {
        var images: [String: UIImage] = [:]
        for key in delta.imageKeys {
            if let url = try? await imageStore.localURL(for: key),
               let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) {
                images[key] = image
            }
        }
        let attributed = (try? NSDeltaCodec.decode(delta.ops, image: { images[$0] }))
            ?? NSMutableAttributedString(string: "\n")
        return (RichTextEditorModel(delta: delta), attributed)
    }

    /// Called once by the representable after it creates the `UITextView`.
    func attach(_ textView: UITextView) {
        self.textView = textView
        selectedRange = textView.selectedRange
        textView.textStorage.delegate = vocabularyGuard
    }

    // MARK: - Selection & typing-attribute hygiene

    /// A marker or an image's identity must never leak onto text the user types next to it —
    /// `richTextImageInfo`/`richTextBlockToken` are custom attributes `typingAttributes` has no
    /// special knowledge of, so `UITextView` will happily propagate one onto the very next
    /// character typed unless something strips it first. Called on every selection change and
    /// after every edit.
    func selectionChanged() {
        guard let textView else { return }
        selectedRange = textView.selectedRange
        var typing = textView.typingAttributes
        if typing[.richTextImageInfo] != nil || typing[.richTextBlockToken] != nil {
            typing[.richTextImageInfo] = nil
            typing[.richTextBlockToken] = nil
            textView.typingAttributes = typing
        }
    }

    // MARK: - Structural edit guarding (the inline-image hazard)

    /// A real hazard of embedding images inline rather than as separate blocks: ordinary typing
    /// can trivially put text on the same line as an attachment. This is the
    /// edit-boundary half of guarding it (see `NSDeltaCodec.encode`'s self-healing for the
    /// belt-and-suspenders other half). Two rules:
    /// - Typing (or pasting) immediately before/after an attachment, with no newline between,
    ///   is redirected to insert a separating newline first.
    /// - Backspacing the newline that immediately follows an attachment deletes the whole
    ///   image instead of merging text onto its line — matching what a user expects
    ///   "delete this line" to do at an image boundary.
    func shouldChangeText(in range: NSRange, replacementText text: String) -> Bool {
        guard let textView else { return true }
        let storage = textView.textStorage
        let length = storage.length

        // Backspace: replacing a non-empty range with "" where that range is exactly the
        // newline right after an attachment.
        if text.isEmpty, range.length == 1, range.location > 0,
           storage.attribute(.richTextImageInfo, at: range.location - 1, effectiveRange: nil) != nil {
            let charAt = (storage.string as NSString).character(at: range.location)
            if charAt == 0x0A {
                deleteImage(atAttachmentIndex: range.location - 1)
                return false
            }
        }

        guard !text.isEmpty else { return true }

        let touchesAttachmentBefore = range.location > 0
            && storage.attribute(.richTextImageInfo, at: range.location - 1, effectiveRange: nil) != nil
        let touchesAttachmentAfter = range.location < length
            && storage.attribute(.richTextImageInfo, at: range.location, effectiveRange: nil) != nil

        guard touchesAttachmentBefore || touchesAttachmentAfter else { return true }

        // Redirect: insert the typed text on its own new line rather than adjacent to the
        // attachment. Simple and conservative — always splits to a fresh line — rather than
        // guessing which side of the attachment the user meant to extend.
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: "\n" + text)
        storage.endEditing()
        textView.selectedRange = NSRange(location: range.location + 1 + (text as NSString).length, length: 0)
        markDirty()
        return false
    }

    private func deleteImage(atAttachmentIndex index: Int) {
        guard let textView else { return }
        let storage = textView.textStorage
        // Removes the attachment character and the newline immediately after it — the whole
        // image, matching what a user expects "delete this line" to do at an image boundary
        // (see docs/ARCHITECTURE.md).
        let deleteLength = min(2, storage.length - index)
        storage.deleteCharacters(in: NSRange(location: index, length: deleteLength))
        textView.selectedRange = NSRange(location: index, length: 0)
        markDirty()
    }

    // MARK: - Inline formatting

    public func toggleBold() { toggleTrait(isBold: true) }
    public func toggleItalic() { toggleTrait(isBold: false) }

    /// Toggles based on the run at the selection's start — matching the common single-toggle
    /// convention (tap once to apply to the whole selection, again to remove), rather than
    /// flipping each run independently. A deliberate simplification over the AttributedString
    /// editor's per-run `transformAttributes`, which SwiftUI's API makes free and this one does
    /// not; revisit if mixed-formatting selections prove confusing in hands-on use.
    private func toggleTrait(isBold: Bool) {
        guard let textView, textView.selectedRange.length > 0 || textView.selectedRange.location >= 0 else { return }
        let range = textView.selectedRange
        let storage = textView.textStorage

        if range.length == 0 {
            let current = currentFont(at: range.location)
            let traits = current.fontDescriptor.symbolicTraits
            let turningOn = isBold ? !traits.contains(.traitBold) : !traits.contains(.traitItalic)
            var typing = textView.typingAttributes
            typing[.font] = fontApplying(isBold ? .traitBold : .traitItalic, on: current, enabled: turningOn)
            textView.typingAttributes = typing
            return
        }

        let anchorFont = currentFont(at: range.location)
        let anchorTraits = anchorFont.fontDescriptor.symbolicTraits
        let turningOn = isBold ? !anchorTraits.contains(.traitBold) : !anchorTraits.contains(.traitItalic)

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? PlatformFont) ?? PlatformFont.preferredFont(forTextStyle: .body)
            storage.addAttribute(.font, value: fontApplying(isBold ? .traitBold : .traitItalic, on: font, enabled: turningOn), range: subrange)
        }
        storage.endEditing()
        markDirty()
    }

    public func toggleUnderline() { toggleUnderlineOrStrike(key: .underlineStyle) }
    public func toggleStrike() { toggleUnderlineOrStrike(key: .strikethroughStyle) }

    private func toggleUnderlineOrStrike(key: NSAttributedString.Key) {
        guard let textView else { return }
        let range = textView.selectedRange
        let storage = textView.textStorage

        if range.length == 0 {
            var typing = textView.typingAttributes
            let isOn = (typing[key] as? Int ?? 0) != 0
            typing[key] = isOn ? nil : NSUnderlineStyle.single.rawValue
            textView.typingAttributes = typing
            return
        }

        let currentlyOn = (storage.attribute(key, at: range.location, effectiveRange: nil) as? Int ?? 0) != 0
        storage.beginEditing()
        if currentlyOn {
            storage.removeAttribute(key, range: range)
        } else {
            storage.addAttribute(key, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        storage.endEditing()
        markDirty()
    }

    public var isBoldActive: Bool { currentFont(at: selectedRange.location).fontDescriptor.symbolicTraits.contains(.traitBold) }
    public var isItalicActive: Bool { currentFont(at: selectedRange.location).fontDescriptor.symbolicTraits.contains(.traitItalic) }
    public var isUnderlineActive: Bool { boolAttribute(.underlineStyle) }
    public var isStrikeActive: Bool { boolAttribute(.strikethroughStyle) }

    private func boolAttribute(_ key: NSAttributedString.Key) -> Bool {
        guard let textView else { return false }
        if textView.selectedRange.length == 0 {
            return (textView.typingAttributes[key] as? Int ?? 0) != 0
        }
        return (textView.textStorage.attribute(key, at: textView.selectedRange.location, effectiveRange: nil) as? Int ?? 0) != 0
    }

    private func currentFont(at index: Int) -> PlatformFont {
        guard let textView else { return .preferredFont(forTextStyle: .body) }
        if textView.selectedRange.length == 0 {
            return (textView.typingAttributes[.font] as? PlatformFont) ?? .preferredFont(forTextStyle: .body)
        }
        let clamped = min(index, max(0, textView.textStorage.length - 1))
        guard textView.textStorage.length > 0 else { return .preferredFont(forTextStyle: .body) }
        return (textView.textStorage.attribute(.font, at: clamped, effectiveRange: nil) as? PlatformFont) ?? .preferredFont(forTextStyle: .body)
    }

    private func fontApplying(_ trait: PlatformFont.Descriptor.SymbolicTraits, on font: PlatformFont, enabled: Bool) -> PlatformFont {
        var traits = font.fontDescriptor.symbolicTraits
        if enabled { traits.insert(trait) } else { traits.remove(trait) }
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
        return PlatformFont(descriptor: descriptor, size: font.pointSize)
    }

    // MARK: - Links

    /// What the link sheet should open with: the range it will act on when saved (`nil` means
    /// "insert brand-new text at the cursor" rather than replace anything), pre-filled text, and
    /// pre-filled URL. An existing link the selection/cursor touches always wins over a plain
    /// selection, and is expanded to its full contiguous run so editing affects the whole link,
    /// not an arbitrary partial sub-selection of it.
    public struct LinkEditContext {
        var range: NSRange?
        var text: String
        var url: URL?
    }

    public var linkEditContext: LinkEditContext {
        guard let textView, textView.textStorage.length > 0 else { return LinkEditContext(range: nil, text: "", url: nil) }
        let storage = textView.textStorage
        let selection = textView.selectedRange
        let nsString = storage.string as NSString

        let seed: Int?
        if selection.length > 0 {
            seed = storage.attribute(.link, at: selection.location, effectiveRange: nil) != nil ? selection.location : nil
        } else if selection.location < storage.length, storage.attribute(.link, at: selection.location, effectiveRange: nil) != nil {
            seed = selection.location
        } else if selection.location > 0, storage.attribute(.link, at: selection.location - 1, effectiveRange: nil) != nil {
            seed = selection.location - 1
        } else {
            seed = nil
        }

        if let seed {
            var range = NSRange(location: 0, length: 0)
            let url = storage.attribute(.link, at: seed, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length)) as? URL
            return LinkEditContext(range: range, text: nsString.substring(with: range), url: url)
        }
        if selection.length > 0 {
            return LinkEditContext(range: selection, text: nsString.substring(with: selection), url: nil)
        }
        return LinkEditContext(range: nil, text: "", url: nil)
    }

    /// The single write path for everything the link sheet supports: turning a selection into a
    /// link, editing an existing link's text and/or URL in place, and inserting brand-new link
    /// text at a bare cursor (`range == nil`) — always by replacing `range` with `text` carrying
    /// `url` as its `.link` attribute, never by leaving old text in place and hoping it still
    /// matches. The replacement's other attributes (bold/italic, if any) come from the range's
    /// first character, or `typingAttributes` for a bare-cursor insert — the same
    /// single-representative-run simplification `toggleTrait` already uses for a mixed selection.
    public func applyLink(text: String, url: URL, range: NSRange?) {
        guard let textView, !text.isEmpty else { return }
        let storage = textView.textStorage
        let target = range ?? NSRange(location: textView.selectedRange.location, length: 0)

        var attributes = target.length > 0
            ? storage.attributes(at: target.location, effectiveRange: nil)
            : textView.typingAttributes
        attributes[.link] = url
        attributes[.richTextBlockToken] = nil
        attributes[.richTextImageInfo] = nil

        storage.beginEditing()
        storage.replaceCharacters(in: target, with: NSAttributedString(string: text, attributes: attributes))
        storage.endEditing()

        textView.selectedRange = NSRange(location: target.location + (text as NSString).length, length: 0)
        markDirty()
    }

    /// Removes a link's URL while keeping its text — the link sheet's "Remove Link" action.
    public func removeLink(range: NSRange) {
        guard let textView, range.length > 0 else { return }
        textView.textStorage.removeAttribute(.link, range: range)
        markDirty()
    }

    // MARK: - Block-level formatting (headers, lists)

    /// The line style of the paragraph the selection currently touches — a single,
    /// mutually-exclusive state, computed from `richTextBlockToken` on the paragraph's
    /// terminating `\n` rather than any class swap.
    public var currentLineStyle: LineStyle {
        guard let textView, let newlineIndex = touchedNewlineIndices(in: textView).first else { return .body }
        let token = textView.textStorage.attribute(.richTextBlockToken, at: newlineIndex, effectiveRange: nil) as? BlockToken
        return Self.lineStyle(from: token)
    }

    private static func lineStyle(from token: BlockToken?) -> LineStyle {
        if case .int(let level)? = token?.attributes["header"] { return level == 1 ? .header1 : .header2 }
        if case .string(let kind)? = token?.attributes["list"] { return kind == "ordered" ? .ordered : .bullet }
        return .body
    }

    /// Every newline terminating a line the current selection touches — a plain cursor touches
    /// just its own line's newline; a multi-line selection touches one per line. Real bug fixed
    /// here, found by hands-on testing: the previous version located only the *last* newline in
    /// `paragraphRange(for:)`'s combined span and wrote the block token there alone, so
    /// selecting five list items and tapping "Bulleted" turned only the last one into a list —
    /// the other four were untouched, and list reconciliation then read that as a single-item
    /// list interrupted by four non-list paragraphs.
    private func touchedNewlineIndices(in textView: UITextView) -> [Int] {
        let storage = textView.textStorage
        guard storage.length > 0 else { return [] }
        let nsString = storage.string as NSString
        let paragraph = nsString.paragraphRange(for: textView.selectedRange)
        guard paragraph.length > 0 else { return [] }

        var indices: [Int] = []
        var index = paragraph.location
        let end = paragraph.location + paragraph.length
        while index < end {
            if nsString.character(at: index) == 0x0A { indices.append(index) }
            index += 1
        }
        // A selection ending exactly at a line's start (no trailing newline within `paragraph`,
        // e.g. the very last line of the document with no terminator yet) still touches that
        // line — fall back to the paragraph's own last character.
        if indices.isEmpty {
            let last = end - 1
            if last >= 0, nsString.character(at: last) == 0x0A { indices.append(last) }
        }
        return indices
    }

    /// Sets the style of every line the selection touches, clearing whichever of header/list
    /// each currently has — header and list are mutually exclusive, matching the toolbar's own
    /// assumption. "Currently active", for a multi-line selection, is read from the first
    /// touched line; tapping the already-active style is "back to Body".
    public func setLineStyle(_ style: LineStyle) {
        guard let textView else { return }
        let newlineIndices = touchedNewlineIndices(in: textView)
        guard !newlineIndices.isEmpty else { return }
        let storage = textView.textStorage

        let newStyle = (style == currentLineStyle) ? .body : style
        var attributes: [String: AttributeValue] = [:]
        switch newStyle {
        case .body: break
        case .header1: attributes["header"] = .int(1)
        case .header2: attributes["header"] = .int(2)
        case .bullet: attributes["list"] = .string("bullet")
        case .ordered: attributes["list"] = .string("ordered")
        }

        storage.beginEditing()
        for newlineIndex in newlineIndices {
            if attributes.isEmpty {
                storage.removeAttribute(.richTextBlockToken, range: NSRange(location: newlineIndex, length: 1))
            } else {
                storage.addAttribute(.richTextBlockToken, value: BlockToken(attributes: attributes), range: NSRange(location: newlineIndex, length: 1))
            }
        }
        storage.endEditing()

        // Re-derive visual styling (paragraph indent/list markers, header size, and — the part
        // that actually needs a whole-document pass — NSTextList instance identity across the
        // paragraphs this change may have just joined or split) from the token, never the other
        // way around.
        NSDeltaCodec.applyVisualBlockStyling(storage)
        markDirty()
    }

    // MARK: - Images

    public func insertImage(key: String, alt: String?, image: UIImage?) {
        guard let textView else { return }
        let storage = textView.textStorage
        var location = textView.selectedRange.location

        storage.beginEditing()
        // Block-level: split the current line first if the cursor is not already at a line
        // start — an image must always begin its own line (see docs/ARCHITECTURE.md).
        if location > 0 {
            let before = (storage.string as NSString).character(at: location - 1)
            if before != 0x0A {
                storage.insert(NSAttributedString(string: "\n"), at: location)
                location += 1
            }
        }
        let attachment = FittedImageTextAttachment()
        attachment.image = image
        let run = NSMutableAttributedString(attachment: attachment)
        run.addAttribute(.richTextImageInfo, value: RichImageAttachmentInfo(key: key, alt: alt), range: NSRange(location: 0, length: run.length))
        run.append(NSAttributedString(string: "\n"))
        storage.insert(run, at: location)
        storage.endEditing()

        textView.selectedRange = NSRange(location: location + run.length, length: 0)
        markDirty()
    }

    // MARK: - Encoding

    /// Called by the coordinator's `textViewDidChange` on every keystroke, and internally by
    /// every formatting mutation in this file. Deliberately not `private`: the representable's
    /// coordinator lives in a different file and needs it for plain typing, which — unlike
    /// bold/list/link — has no dedicated model method of its own to route through.
    func markDirty() {
        isDirty = true
        selectionChanged()
        // Covers programmatic mutations (insert image, toggle list) that never pass through a
        // delegate callback of their own — see `RichTextEditorUITextView`'s doc comment.
        textView?.invalidateIntrinsicContentSize()
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.encodeIfChanged()
        }
    }

    @discardableResult
    public func encodeIfChanged() -> Bool {
        debounceTask?.cancel()
        guard let textView else { return false }
        let encoded = Delta(ops: NSDeltaCodec.encode(textView.textStorage))
        let violations = encoded.vocabularyViolations()
        guard violations.isEmpty else {
            integrityFailure = "Editing produced an invalid document: \(violations.map(\.description).joined(separator: "; "))"
            return false
        }
        integrityFailure = nil
        guard encoded != savedDelta else {
            isDirty = false
            return false
        }
        savedDelta = encoded
        isDirty = false
        return true
    }

    public var matchesOriginal: Bool {
        guard let textView else { return true }
        return Delta(ops: NSDeltaCodec.encode(textView.textStorage)) == originalDelta
    }

    public func reportError(_ message: String) { lastError = message }
    public func clearErrors() { lastError = nil; integrityFailure = nil }
}
#endif
