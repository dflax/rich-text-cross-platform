import Foundation
import SwiftUI

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

    /// Point sizes for the two header levels. Chosen to read as headings next to body text
    /// without `Font.TextStyle`, because a concrete size is what survives being embedded in an
    /// `AttributedString` alongside inline emphasis.
    static func font(for kind: Block.Kind) -> Font {
        switch kind {
        case .header(1): .system(size: 28, weight: .bold)
        case .header: .system(size: 22, weight: .bold)
        default: .body
        }
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

    /// Matches the edit path's own indent exactly (`NSDeltaCodec.applyVisualBlockStyling`) so a
    /// list item looks the same whether it's being edited or read. Deliberately does NOT set
    /// `textLists` - the marker is already baked into the characters here (unlike the edit path,
    /// where TextKit draws it), so a renderer that also honors `textLists` would draw the marker
    /// twice.
    ///
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
    private static func listParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.headIndent = 28
        style.firstLineHeadIndent = 0
        return style
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
                if !marker.isEmpty {
                    var markerText = AttributedString(marker)
                    markerText.font = font(for: block.kind)
                    line.append(markerText)
                }

                var body = block.inline
                // Setting the font at the line level leaves inline emphasis to
                // `inlinePresentationIntent`, so bold inside a heading still reads as bolder
                // than the heading rather than fighting it.
                body.font = font(for: block.kind)
                line.append(body)

                var lineListStyle: NSParagraphStyle?
                switch block.kind {
                case .bullet, .ordered:
                    let style = listParagraphStyle()
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
