import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias PlatformFontAttribute = AttributeScopes.UIKitAttributes.FontAttribute
private typealias PlatformUnderlineStyleAttribute = AttributeScopes.UIKitAttributes.UnderlineStyleAttribute
private typealias PlatformStrikethroughStyleAttribute = AttributeScopes.UIKitAttributes.StrikethroughStyleAttribute
#elseif canImport(AppKit)
import AppKit
private typealias PlatformFontAttribute = AttributeScopes.AppKitAttributes.FontAttribute
private typealias PlatformUnderlineStyleAttribute = AttributeScopes.AppKitAttributes.UnderlineStyleAttribute
private typealias PlatformStrikethroughStyleAttribute = AttributeScopes.AppKitAttributes.StrikethroughStyleAttribute
#endif

/// Groups rendered blocks into the largest possible spans of selectable text.
///
/// ## Why this exists
///
/// The requirement here is specific: reading a document must support "real, native, continuous
/// drag-to-select text … **no per-paragraph limitation**." That rules out the obvious implementation. A
/// `VStack` of one `Text` per block with `.textSelection(.enabled)` gives selection *within*
/// each `Text` and nowhere across them — which is exactly the per-paragraph limitation the
/// production app is being criticised for, reproduced in a new shape.
///
/// SwiftUI will only carry a selection across a contiguous run of characters inside a single
/// `Text`. So the read view renders **one `Text` per span of consecutive non-image blocks**,
/// with headers and list markers baked into the `AttributedString` rather than expressed as
/// separate views. Selection is then continuous across paragraphs, headings and list items,
/// and breaks only at an image — which is unavoidable, and defensible, since an image genuinely
/// interrupts the text.
///
/// The cost is that headers and list markers are text styling rather than view structure. That
/// is a real trade and it is the read path's alone: the Delta still carries `header` and `list`
/// as block attributes, the edit path still round-trips them as opaque metadata, and nothing
/// here ever feeds back into a document.
public enum ReadLayout {

    public struct Group: Identifiable, Equatable {
        public enum Content: Equatable {
            /// One or more consecutive text blocks, flattened into a single selectable run.
            case text(AttributedString)
            case image(key: String, alt: String?)
            case mergeField(name: String)
        }

        public let id: Int
        public let content: Content
    }

    /// Concrete point size standing in for body text (matches `UIFont.preferredFont(forTextStyle:
    /// .body)`'s own default-Dynamic-Type resolution on iOS).
    ///
    /// **Correction to a claim in this file's own history (and in the now-superseded parts of
    /// `docs/guides/read-only-rendering.md`):** an earlier pass believed switching this from the
    /// semantic `Font.TextStyle` value `.body` to this concrete `.system(size: 17)` was sufficient
    /// to fix a too-small-font bug in a real `UITextView`/`NSTextView` host. It was not. Direct
    /// measurement (bridging a `.system(size: 17)` `AttributedString` through
    /// `NSAttributedString(_:)` and inspecting the result) shows **no SwiftUI `Font` value, concrete
    /// or semantic, survives that bridge at all** — every one lands under a raw, uninterpreted
    /// custom key (`NSAttributedStringKey(_rawValue: "SwiftUI.Font")`) carrying the original,
    /// unconverted `Font` object, not a real `UIFont`/`NSFont` under the standard `.font` key.
    /// `Text(AttributedString)` never depended on that bridge for its own rendering — it resolves
    /// `Font` through its own internal SwiftUI-native pipeline — which is why this was invisible
    /// there. The same gap affects `inlinePresentationIntent` (bold/italic), `.underlineStyle`, and
    /// `.strikethroughStyle`: all four bridge to raw, uninterpreted custom keys, not real font
    /// traits or `NSAttributedString.Key.underlineStyle`/`.strikethroughStyle` values. See
    /// `platformBaseFont(for:)` and `addingPlatformAttributes(baseFont:to:)` for the actual fix —
    /// setting the platform-scoped attribute (`AttributeScopes.UIKitAttributes`/`AppKitAttributes`)
    /// *alongside* the SwiftUI-scoped one, confirmed by direct measurement to produce a real,
    /// retrievable `PlatformFont` under the standard `.font` key.
    private static let bodyPointSize: CGFloat = 17

    /// Point sizes for the two header levels, and the body default above. Sets only the
    /// SwiftUI-scoped `Font` attribute — kept for `Text`-based consumers, which resolve `Font`
    /// through their own native pipeline. See `platformBaseFont(for:)` for the platform-scoped
    /// counterpart a real `UITextView`/`NSTextView` needs (`bodyPointSize`'s doc comment explains
    /// why both are necessary).
    static func font(for kind: Block.Kind) -> Font {
        switch kind {
        case .header(1): .system(size: 28, weight: .bold)
        case .header: .system(size: 22, weight: .bold)
        default: .system(size: bodyPointSize)
        }
    }

    /// The platform-scoped counterpart to `font(for:)`, same sizes/weights, for a real
    /// `UITextView`/`NSTextView` host — see `bodyPointSize`'s doc comment for why both are needed.
    private static func platformBaseFont(for kind: Block.Kind) -> PlatformFont {
        switch kind {
        case .header(1): PlatformFont.systemFont(ofSize: 28, weight: .bold)
        case .header: PlatformFont.systemFont(ofSize: 22, weight: .bold)
        default: PlatformFont.systemFont(ofSize: bodyPointSize)
        }
    }

    /// Merges bold/italic traits into `font` when set. `inlinePresentationIntent` (how bold/italic
    /// are represented on `AttributedString`, per `DeltaRenderer`) does not survive bridging to
    /// `NSAttributedString` as real font traits either — see `bodyPointSize`'s doc comment — so a
    /// real text view needs them baked into an actual `PlatformFont` per run, same as the base size.
    private static func mergingTraits(bold: Bool, italic: Bool, into font: PlatformFont) -> PlatformFont {
        guard bold || italic else { return font }
        #if canImport(UIKit)
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
        #elseif canImport(AppKit)
        var result = font
        if bold { result = NSFontManager.shared.convert(result, toHaveTrait: .boldFontMask) }
        if italic { result = NSFontManager.shared.convert(result, toHaveTrait: .italicFontMask) }
        return result
        #endif
    }

    /// Adds the platform-scoped font/underline/strikethrough attributes a real `UITextView`/
    /// `NSTextView` needs, per run, on top of whatever SwiftUI-scoped attributes `body.font` and
    /// `DeltaRenderer` already set (left untouched, for `Text`-based consumers). Per-run rather
    /// than whole-string so inline bold/italic inside a heading merges with the heading's own base
    /// font instead of overwriting it.
    private static func addingPlatformAttributes(baseFont: PlatformFont, to attributed: AttributedString) -> AttributedString {
        var result = attributed
        for run in attributed.runs {
            let isBold = run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
            let isItalic = run.inlinePresentationIntent?.contains(.emphasized) == true
            result[run.range][PlatformFontAttribute.self] = mergingTraits(bold: isBold, italic: isItalic, into: baseFont)
            if run.underlineStyle != nil {
                result[run.range][PlatformUnderlineStyleAttribute.self] = .single
            }
            if run.strikethroughStyle != nil {
                result[run.range][PlatformStrikethroughStyleAttribute.self] = .single
            }
        }
        return result
    }

    /// The visible marker a list item carries. Baked into the text because the whole span has
    /// to live in one `Text` for selection to cross it.
    static func marker(for kind: Block.Kind) -> String {
        switch kind {
        case .bullet: "•  "
        case .ordered(let number): "\(number).  "
        default: ""
        }
    }

    /// **Known limitation, real hands-on device finding, not yet worked around at this layer:**
    /// SwiftUI's `Text(AttributedString)` silently ignores `.paragraphStyle` entirely - confirmed
    /// by direct measurement (an `NSHostingView` wrapping an indented vs. non-indented `Text` at
    /// the same fixed width produced byte-identical fitting heights). A host rendering `.text`
    /// groups via plain SwiftUI `Text` gets no visible hanging indent: a wrapped list item's
    /// continuation line falls flush under the marker instead of aligning with the first line's
    /// text. This attribute is real and round-trips correctly through `AttributedString` (also
    /// confirmed directly) for any host willing to render through a real text-kit-backed surface
    /// (`UITextView`/`NSTextView`, `isEditable = false`) instead of `Text` - see
    /// `docs/guides/read-only-rendering.md`.
    ///
    /// `headIndent` is measured from the marker's own actual rendered width at the body point
    /// size, not a fixed constant copied from the edit path's `NSDeltaCodec.
    /// applyVisualBlockStyling` - that value was tuned for `NSTextList`'s own marker-drawing
    /// conventions, not a literal marker string, and a fixed value here would visibly misalign a
    /// two-digit ordered item ("10.  ", wider than "1.  ") against a bullet's own indent. Real bug,
    /// found by hands-on device testing: a first attempt at this hardcoded `headIndent = 28`,
    /// which read as "wrapping in too far" once the body font size above was also corrected to a
    /// real 17pt (the marker's own width grows with the font, and 28 was never derived from either
    /// value in the first place). Deliberately does NOT set `textLists` - the marker is already
    /// baked into the characters here (unlike the edit path, where TextKit draws it), so a
    /// renderer that also honors `textLists` would draw the marker twice.
    private static func listParagraphStyle(markerWidth: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.headIndent = ceil(markerWidth)
        style.firstLineHeadIndent = 0
        return style
    }

    private static func measuredWidth(of marker: String, pointSize: CGFloat) -> CGFloat {
        (marker as NSString).size(withAttributes: [.font: PlatformFont.systemFont(ofSize: pointSize)]).width
    }

    private static func applyingListStyle(_ style: NSParagraphStyle, to attributed: AttributedString) -> AttributedString {
        let mutable = NSMutableAttributedString(attributed)
        mutable.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: mutable.length))
        return AttributedString(mutable)
    }

    public static func groups(from blocks: [Block]) -> [Group] {
        var groups: [Group] = []
        var pending = AttributedString()
        var pendingIsEmpty = true
        // The style the SEPARATOR about to be appended (which terminates the line just added,
        // not the one about to start) should carry - mirrors `NSDeltaCodec.
        // applyVisualBlockStyling`'s own `paragraphRange.length + 1`, so a list item's own
        // trailing newline shares its hanging indent rather than reading as unstyled. `nil` for
        // a separator that terminates a non-list line, so a list item is never followed by a
        // stray indent bleeding onto the next, unrelated paragraph.
        var previousLineListStyle: NSParagraphStyle?

        func flushText() {
            guard !pendingIsEmpty else { return }
            groups.append(Group(id: groups.count, content: .text(pending)))
            pending = AttributedString()
            pendingIsEmpty = true
            previousLineListStyle = nil
        }

        for block in blocks {
            switch block.kind {
            case .image(let key, let alt):
                flushText()
                groups.append(Group(id: groups.count, content: .image(key: key, alt: alt)))

            case .mergeField(let name):
                flushText()
                groups.append(Group(id: groups.count, content: .mergeField(name: name)))

            case .paragraph, .header, .bullet, .ordered:
                // Blocks within a span are joined by newlines. A blank line in the source is a
                // block with empty inline content, so it still contributes its separator and
                // the spacing the author intended survives.
                if !pendingIsEmpty {
                    var separator = AttributedString("\n")
                    if let previousLineListStyle {
                        separator = applyingListStyle(previousLineListStyle, to: separator)
                    }
                    pending.append(separator)
                }

                var line = AttributedString()
                let marker = marker(for: block.kind)
                let baseFont = platformBaseFont(for: block.kind)
                if !marker.isEmpty {
                    var markerText = AttributedString(marker)
                    markerText.font = font(for: block.kind)
                    markerText[PlatformFontAttribute.self] = baseFont
                    line.append(markerText)
                }

                var body = block.inline
                // Setting the font at the line level leaves inline emphasis to
                // `inlinePresentationIntent`, so bold inside a heading still reads as bolder
                // than the heading rather than fighting it.
                body.font = font(for: block.kind)
                body = addingPlatformAttributes(baseFont: baseFont, to: body)
                line.append(body)

                var lineListStyle: NSParagraphStyle?
                switch block.kind {
                case .bullet, .ordered:
                    let width = measuredWidth(of: marker, pointSize: bodyPointSize)
                    let style = listParagraphStyle(markerWidth: width)
                    line = applyingListStyle(style, to: line)
                    lineListStyle = style
                default:
                    break
                }

                pending.append(line)
                pendingIsEmpty = false
                previousLineListStyle = lineListStyle
            }
        }

        flushText()
        return groups
    }

    /// Convenience for the common path: Delta straight to groups.
    public static func groups(from delta: Delta) -> [Group] {
        groups(from: DeltaRenderer.blocks(from: delta))
    }
}
