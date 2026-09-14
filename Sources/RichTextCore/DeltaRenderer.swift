import Foundation
import SwiftUI

/// One rendered line of a document.
///
/// The read path's whole job is turning a Delta into these. Note there is no round-trip
/// obligation here at all — `Block` is a one-way projection for display. That asymmetry is
/// deliberate: the read path is the hot path (everyone reads, a handful of admins edit), so
/// it gets to be simple and render richer structure than `TextEditor` can, while the edit
/// path carries the byte-identical burden.
public struct Block: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case paragraph
        case header(Int)
        case bullet
        /// Carries its own number so the view never has to reconstruct list numbering.
        case ordered(Int)
        case image(key: String, alt: String?)
        /// P10 spike shape. Rendered as a distinct, non-editable chip.
        case mergeField(name: String)
    }

    public let id: Int
    public let kind: Kind
    /// Empty for `.image` and `.mergeField` — an embed never touches an `AttributedString`,
    /// which is exactly why images cost the read path nothing.
    public let inline: AttributedString

    public init(id: Int, kind: Kind, inline: AttributedString = AttributedString()) {
        self.id = id
        self.kind = kind
        self.inline = inline
    }
}

public enum DeltaRenderer {
    public static func blocks(from deltaJSON: Data) throws -> [Block] {
        blocks(from: try Delta.decode(json: deltaJSON))
    }

    /// Splits the ops on newline characters. Each newline's attributes determine its
    /// block's `Kind`; the text runs preceding it become the block's inline
    /// `AttributedString`.
    public static func blocks(from delta: Delta) -> [Block] {
        var blocks: [Block] = []
        var pendingRuns: [(text: String, attributes: [String: AttributeValue]?)] = []
        var orderedNumber = 0
        // Set after emitting an image block. The newline that immediately follows an image
        // terminates the image's own line, so it must not also close an empty paragraph —
        // that would insert a phantom blank line under every image.
        var awaitingEmbedNewline = false

        func kind(for blockAttributes: [String: AttributeValue]?) -> Block.Kind {
            if case .int(let level)? = blockAttributes?["header"], Vocabulary.headerLevels.contains(level) {
                return .header(level)
            }
            if case .string(let list)? = blockAttributes?["list"] {
                switch list {
                case "bullet": return .bullet
                case "ordered": return .ordered(orderedNumber + 1)
                default: break
                }
            }
            return .paragraph
        }

        func closeLine(blockAttributes: [String: AttributeValue]?) {
            let lineKind = kind(for: blockAttributes)
            if case .ordered = lineKind { orderedNumber += 1 } else { orderedNumber = 0 }
            var inline = AttributedString()
            for run in pendingRuns {
                inline.append(attributed(run.text, run.attributes))
            }
            blocks.append(Block(id: blocks.count, kind: lineKind, inline: inline))
            pendingRuns.removeAll(keepingCapacity: true)
        }

        func emitEmbed(_ kind: Block.Kind) {
            // Defensive: the vocabulary forbids an embed sharing a line with text, but a
            // renderer that silently swallowed the text would hide the violation instead of
            // showing it. Flush what is pending as its own line and carry on.
            if !pendingRuns.isEmpty { closeLine(blockAttributes: nil) }
            blocks.append(Block(id: blocks.count, kind: kind))
            orderedNumber = 0
            awaitingEmbedNewline = true
        }

        for op in delta.ops {
            switch op.insert {
            case .embed(.image(let key)):
                var alt: String?
                if case .string(let value)? = op.attributes?["alt"] { alt = value }
                emitEmbed(.image(key: key, alt: alt))

            case .embed(.mergeField(let name)):
                emitEmbed(.mergeField(name: name))

            case .text(let string):
                // An op's attributes serve two roles at once: inline formatting for its text
                // characters, block formatting for its newline characters. Splitting them
                // here keeps a run like {"insert":"a\n","attributes":{"bold":true}} from
                // trying to make the line a header, or vice versa.
                let inlineAttributes = op.attributes?.filter { Vocabulary.inlineAttributes.contains($0.key) }
                let blockAttributes = op.attributes?.filter { Vocabulary.blockAttributes.contains($0.key) }
                var buffer = ""

                for character in string {
                    guard character == "\n" else {
                        buffer.append(character)
                        continue
                    }
                    if !buffer.isEmpty {
                        pendingRuns.append((buffer, inlineAttributes))
                        buffer = ""
                    }
                    if awaitingEmbedNewline {
                        awaitingEmbedNewline = false
                        // The embed already produced its block; this newline just terminates
                        // it. Anything that had accumulated before it belongs to a line of
                        // its own (only reachable on malformed input).
                        if !pendingRuns.isEmpty { closeLine(blockAttributes: blockAttributes) }
                        continue
                    }
                    closeLine(blockAttributes: blockAttributes)
                }

                if !buffer.isEmpty {
                    pendingRuns.append((buffer, inlineAttributes))
                }
            }
        }

        // A well-formed document always ends with a newline, so this only fires on malformed
        // input. Rendering the trailing text is better than dropping it on the floor.
        if !pendingRuns.isEmpty {
            closeLine(blockAttributes: nil)
        }

        return blocks
    }

    /// Applies the inline vocabulary to a text run.
    ///
    /// Bold and italic go through `inlinePresentationIntent` rather than a concrete font so
    /// the block-level view stays free to pick the font — a header needs a larger face, and
    /// baking one in here would fight that.
    static func attributed(_ text: String, _ attributes: [String: AttributeValue]?) -> AttributedString {
        var string = AttributedString(text)
        guard let attributes else { return string }

        var intent: InlinePresentationIntent = []
        if case .bool(true)? = attributes["bold"] { intent.insert(.stronglyEmphasized) }
        if case .bool(true)? = attributes["italic"] { intent.insert(.emphasized) }
        if !intent.isEmpty { string.inlinePresentationIntent = intent }

        if case .bool(true)? = attributes["underline"] { string.underlineStyle = .single }
        if case .bool(true)? = attributes["strike"] { string.strikethroughStyle = .single }
        // A link whose URL the system cannot parse is left as plain text rather than
        // dropped — the words still have to reach the reader.
        if case .string(let urlString)? = attributes["link"], let url = URL(string: urlString) {
            string.link = url
        }

        return string
    }
}
