#if canImport(AppKit)
import AppKit
import Foundation
import Observation
import RichTextCore

/// State for one editing session — the macOS counterpart of the iOS `RichTextEditorModel`
/// (declared under `#if canImport(UIKit)` in `RichTextEditorModel.swift`). Same public type name
/// on both platforms, implemented in mutually-exclusive files, so a consumer (the public
/// `RichTextEditor` view, `RichTextFormatBar`, a custom toolbar) never needs to know which
/// platform it's running on — see `docs/ARCHITECTURE.md`.
///
/// Same architectural choice as the iOS model: no separate `document` copy. `NSTextView.textStorage`
/// **is** the document while editing; this model holds a weak reference to the text view and
/// reads/writes through it directly.
///
/// **Selection is collapsed to `selectedRanges.first`.** `NSTextView` has no single-range
/// property the way `UITextView` does — `selectedRanges: [NSValue]` exists because AppKit
/// supports discontiguous multi-range selection. This editor's vocabulary and toolbar are built
/// around a single active range (matching the iOS editor's UX exactly); multi-range selection is
/// not a feature this editor exposes on either platform, so collapsing here is a deliberate
/// choice, not an oversight. See `docs/ROADMAP.md`.
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

    /// Mirrors `textView.selectedRanges.first`, updated by the coordinator's
    /// `textViewDidChangeSelection`. A plain stored value (not read live from the text view) so
    /// SwiftUI's `@Observable` tracking actually fires when the toolbar needs to re-render its
    /// active-state highlighting.
    public private(set) var selectedRange = NSRange(location: 0, length: 0)

    weak var textView: NSTextView?

    /// The vocabulary-enforcement backstop — `NSTextStorage.delegate` is a weak/unowned
    /// reference, so this model is what keeps it alive for as long as the text view is attached.
    /// Paste interception (`RichTextEditorNSTextView.paste(_:)`) is the primary control; this
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
        var images: [String: NSImage] = [:]
        for key in delta.imageKeys {
            if let url = try? await imageStore.localURL(for: key),
               let image = NSImage(contentsOfFile: url.path(percentEncoded: false)) {
                images[key] = image
            }
        }
        let attributed = (try? NSDeltaCodec.decode(delta.ops, image: { images[$0] }))
            ?? NSMutableAttributedString(string: "\n")
        return (RichTextEditorModel(delta: delta), attributed)
    }

    /// Called once by the representable after it creates the `NSTextView`.
    func attach(_ textView: NSTextView) {
        self.textView = textView
        selectedRange = Self.selectedRange(of: textView)
        textView.textStorage?.delegate = vocabularyGuard
    }

    private static func selectedRange(of textView: NSTextView) -> NSRange {
        textView.selectedRanges.first?.rangeValue ?? NSRange(location: 0, length: 0)
    }

    private func setSelectedRange(_ range: NSRange) {
        textView?.selectedRanges = [NSValue(range: range)]
    }

    // MARK: - Selection & typing-attribute hygiene

    /// A marker or an image's identity must never leak onto text the user types next to it —
    /// `richTextImageInfo`/`richTextBlockToken` are custom attributes `typingAttributes` has no
    /// special knowledge of, so `NSTextView` will happily propagate one onto the very next
    /// character typed unless something strips it first. Called on every selection change and
    /// after every edit.
    func selectionChanged() {
        guard let textView else { return }
        selectedRange = Self.selectedRange(of: textView)
        var typing = textView.typingAttributes
        if typing[.richTextImageInfo] != nil || typing[.richTextBlockToken] != nil {
            typing[.richTextImageInfo] = nil
            typing[.richTextBlockToken] = nil
            textView.typingAttributes = typing
        }
    }

    // MARK: - Structural edit guarding (the inline-image hazard)

    /// A real hazard of embedding images inline rather than as separate blocks: ordinary typing
    /// can trivially put text on the same line as an attachment. This is the edit-boundary half
    /// of guarding it (see `NSDeltaCodec.encode`'s self-healing for the belt-and-suspenders other
    /// half). Two rules:
    /// - Typing (or pasting) immediately before/after an attachment, with no newline between, is
    ///   redirected to insert a separating newline first.
    /// - Backspacing the newline that immediately follows an attachment deletes the whole image
    ///   instead of merging text onto its line — matching what a user expects "delete this line"
    ///   to do at an image boundary.
    func shouldChangeText(in range: NSRange, replacementText text: String) -> Bool {
        guard let textView, let storage = textView.textStorage else { return true }
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
        setSelectedRange(NSRange(location: range.location + 1 + (text as NSString).length, length: 0))
        markDirty()
        return false
    }

    private func deleteImage(atAttachmentIndex index: Int) {
        guard let textView, let storage = textView.textStorage else { return }
        // Removes the attachment character and the newline immediately after it — the whole
        // image, matching what a user expects "delete this line" to do at an image boundary.
        let deleteLength = min(2, storage.length - index)
        storage.deleteCharacters(in: NSRange(location: index, length: deleteLength))
        setSelectedRange(NSRange(location: index, length: 0))
        markDirty()
    }

    // MARK: - Inline formatting

    public func toggleBold() { toggleTrait(isBold: true) }
    public func toggleItalic() { toggleTrait(isBold: false) }

    /// Toggles based on the run at the selection's start — matching the common single-toggle
    /// convention (tap once to apply to the whole selection, again to remove), rather than
    /// flipping each run independently.
    private func toggleTrait(isBold: Bool) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = Self.selectedRange(of: textView)

        if range.length == 0 {
            let current = currentFont(at: range.location)
            let traits = current.fontDescriptor.symbolicTraits
            let turningOn = isBold ? !traits.contains(.bold) : !traits.contains(.italic)
            var typing = textView.typingAttributes
            typing[.font] = fontApplying(isBold ? .bold : .italic, on: current, enabled: turningOn)
            textView.typingAttributes = typing
            return
        }

        let anchorFont = currentFont(at: range.location)
        let anchorTraits = anchorFont.fontDescriptor.symbolicTraits
        let turningOn = isBold ? !anchorTraits.contains(.bold) : !anchorTraits.contains(.italic)

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? PlatformFont) ?? PlatformFont.preferredFont(forTextStyle: .body)
            storage.addAttribute(.font, value: fontApplying(isBold ? .bold : .italic, on: font, enabled: turningOn), range: subrange)
        }
        storage.endEditing()
        markDirty()
    }

    public func toggleUnderline() { toggleUnderlineOrStrike(key: .underlineStyle) }
    public func toggleStrike() { toggleUnderlineOrStrike(key: .strikethroughStyle) }

    private func toggleUnderlineOrStrike(key: NSAttributedString.Key) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = Self.selectedRange(of: textView)

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

    public var isBoldActive: Bool { currentFont(at: selectedRange.location).fontDescriptor.symbolicTraits.contains(.bold) }
    public var isItalicActive: Bool { currentFont(at: selectedRange.location).fontDescriptor.symbolicTraits.contains(.italic) }
    public var isUnderlineActive: Bool { boolAttribute(.underlineStyle) }
    public var isStrikeActive: Bool { boolAttribute(.strikethroughStyle) }

    private func boolAttribute(_ key: NSAttributedString.Key) -> Bool {
        guard let textView, let storage = textView.textStorage else { return false }
        let range = Self.selectedRange(of: textView)
        if range.length == 0 {
            return (textView.typingAttributes[key] as? Int ?? 0) != 0
        }
        return (storage.attribute(key, at: range.location, effectiveRange: nil) as? Int ?? 0) != 0
    }

    private func currentFont(at index: Int) -> PlatformFont {
        guard let textView, let storage = textView.textStorage else { return .preferredFont(forTextStyle: .body) }
        let range = Self.selectedRange(of: textView)
        if range.length == 0 {
            return (textView.typingAttributes[.font] as? PlatformFont) ?? .preferredFont(forTextStyle: .body)
        }
        guard storage.length > 0 else { return .preferredFont(forTextStyle: .body) }
        let clamped = min(index, max(0, storage.length - 1))
        return (storage.attribute(.font, at: clamped, effectiveRange: nil) as? PlatformFont) ?? .preferredFont(forTextStyle: .body)
    }

    private func fontApplying(_ trait: NSFontDescriptor.SymbolicTraits, on font: PlatformFont, enabled: Bool) -> PlatformFont {
        var traits = font.fontDescriptor.symbolicTraits
        if enabled { traits.insert(trait) } else { traits.remove(trait) }
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return PlatformFont(descriptor: descriptor, size: font.pointSize) ?? font
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
        guard let textView, let storage = textView.textStorage, storage.length > 0 else {
            return LinkEditContext(range: nil, text: "", url: nil)
        }
        let selection = Self.selectedRange(of: textView)
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
    /// matches.
    public func applyLink(text: String, url: URL, range: NSRange?) {
        guard let textView, let storage = textView.textStorage, !text.isEmpty else { return }
        let target = range ?? NSRange(location: Self.selectedRange(of: textView).location, length: 0)

        var attributes = target.length > 0
            ? storage.attributes(at: target.location, effectiveRange: nil)
            : textView.typingAttributes
        attributes[.link] = url
        attributes[.richTextBlockToken] = nil
        attributes[.richTextImageInfo] = nil

        storage.beginEditing()
        storage.replaceCharacters(in: target, with: NSAttributedString(string: text, attributes: attributes))
        storage.endEditing()

        setSelectedRange(NSRange(location: target.location + (text as NSString).length, length: 0))
        markDirty()
    }

    /// Removes a link's URL while keeping its text — the link sheet's "Remove Link" action.
    public func removeLink(range: NSRange) {
        guard let textView, let storage = textView.textStorage, range.length > 0 else { return }
        storage.removeAttribute(.link, range: range)
        markDirty()
    }

    // MARK: - Block-level formatting (headers, lists)

    /// The line style of the paragraph the selection currently touches, computed from
    /// `richTextBlockToken` on the paragraph's terminating `\n` rather than any class swap.
    public var currentLineStyle: LineStyle {
        guard let textView, let storage = textView.textStorage,
              let newlineIndex = touchedNewlineIndices(in: textView, storage: storage).first
        else { return .body }
        let token = storage.attribute(.richTextBlockToken, at: newlineIndex, effectiveRange: nil) as? BlockToken
        return Self.lineStyle(from: token)
    }

    private static func lineStyle(from token: BlockToken?) -> LineStyle {
        if case .int(let level)? = token?.attributes["header"] { return level == 1 ? .header1 : .header2 }
        if case .string(let kind)? = token?.attributes["list"] { return kind == "ordered" ? .ordered : .bullet }
        return .body
    }

    /// Every newline terminating a line the current selection touches — a plain cursor touches
    /// just its own line's newline; a multi-line selection touches one per line.
    private func touchedNewlineIndices(in textView: NSTextView, storage: NSTextStorage) -> [Int] {
        guard storage.length > 0 else { return [] }
        let nsString = storage.string as NSString
        let paragraph = nsString.paragraphRange(for: Self.selectedRange(of: textView))
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
        guard let textView, let storage = textView.textStorage else { return }
        let newlineIndices = touchedNewlineIndices(in: textView, storage: storage)
        guard !newlineIndices.isEmpty else { return }

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

        // Re-derive visual styling (paragraph indent/list markers, header size, and NSTextList
        // instance identity across the paragraphs this change may have just joined or split)
        // from the token, never the other way around.
        NSDeltaCodec.applyVisualBlockStyling(storage)
        markDirty()
    }

    // MARK: - Images

    public func insertImage(key: String, alt: String?, image: NSImage?) {
        guard let textView, let storage = textView.textStorage else { return }
        var location = Self.selectedRange(of: textView).location

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

        setSelectedRange(NSRange(location: location + run.length, length: 0))
        markDirty()
    }

    // MARK: - Encoding

    /// Called by the coordinator's `textDidChange` on every keystroke, and internally by every
    /// formatting mutation in this file.
    func markDirty() {
        isDirty = true
        selectionChanged()
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
        guard let textView, let storage = textView.textStorage else { return false }
        let encoded = Delta(ops: NSDeltaCodec.encode(storage))
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
        guard let textView, let storage = textView.textStorage else { return true }
        return Delta(ops: NSDeltaCodec.encode(storage)) == originalDelta
    }

    public func reportError(_ message: String) { lastError = message }
    public func clearErrors() { lastError = nil; integrityFailure = nil }
}
#endif
