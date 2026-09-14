import Foundation

/// The shared formatting vocabulary, and the structural rules that go with it.
///
/// Both clients are constrained to exactly this set — nothing outside it may ever be
/// produced by either editor. The PRD is explicit that every attribute added is a new
/// round-trip failure mode, so this type exists to make "in the vocabulary" a thing that
/// is checked rather than assumed.
public enum Vocabulary {
    /// Attributes that live on a text run.
    public static let inlineAttributes: Set<String> = ["bold", "italic", "underline", "strike", "link"]

    /// Attributes that live on the `\n` that terminates a line, not on the text run.
    public static let blockAttributes: Set<String> = ["header", "list"]

    /// Attributes permitted on an image embed.
    public static let embedAttributes: Set<String> = ["alt"]

    public static let headerLevels: Set<Int> = [1, 2]
    public static let listKinds: Set<String> = ["bullet", "ordered"]
}

public enum VocabularyViolation: Error, Equatable, CustomStringConvertible {
    case unknownAttribute(index: Int, name: String)
    case wrongAttributeType(index: Int, name: String)
    case headerLevelOutOfRange(index: Int, level: Int)
    case unknownListKind(index: Int, kind: String)
    case blockAttributeOnNonNewline(index: Int, name: String)
    case inlineAttributeOnNewlineRun(index: Int, name: String)
    case inlineAttributeOnEmbed(index: Int, name: String)
    case attributeOnMultiCharacterNewlineRun(index: Int, name: String)
    case imageNotFollowedByNewline(index: Int)
    case imageNotPrecededByNewline(index: Int)
    case imageReferenceIsURL(index: Int, value: String)
    case blockAttributeOnImageTerminator(index: Int, name: String)
    case documentDoesNotEndWithNewline
    case emptyTextInsert(index: Int)
    case mergeFieldNotEnabled(index: Int)

    public var description: String {
        switch self {
        case .unknownAttribute(let i, let name):
            "Op \(i) carries \"\(name)\", which is not in the vocabulary."
        case .wrongAttributeType(let i, let name):
            "Op \(i)'s \"\(name)\" has the wrong value type for the vocabulary."
        case .headerLevelOutOfRange(let i, let level):
            "Op \(i) has header level \(level); the vocabulary allows only 1 and 2."
        case .unknownListKind(let i, let kind):
            "Op \(i) has list kind \"\(kind)\"; the vocabulary allows only bullet and ordered."
        case .blockAttributeOnNonNewline(let i, let name):
            "Op \(i) carries the block attribute \"\(name)\" but is not a newline run. Block attributes attach to the \\n that terminates a line."
        case .inlineAttributeOnNewlineRun(let i, let name):
            "Op \(i) carries the inline attribute \"\(name)\" on a run containing a newline. Inline marks render as nothing on a newline, Quill never emits them, and the codec drops them on encode — so this cannot round-trip."
        case .inlineAttributeOnEmbed(let i, let name):
            "Op \(i) is an embed carrying the inline attribute \"\(name)\"."
        case .attributeOnMultiCharacterNewlineRun(let i, let name):
            "Op \(i) carries the block attribute \"\(name)\" but inserts more than one newline, so it is ambiguous which line the attribute terminates."
        case .imageNotFollowedByNewline(let i):
            "The image at op \(i) is not immediately followed by a newline insert. Images are block-level only."
        case .imageNotPrecededByNewline(let i):
            "The image at op \(i) does not start a line. Images are block-level only: one may never sit between two text runs on the same line."
        case .imageReferenceIsURL(let i, let value):
            "The image at op \(i) references \"\(value)\", which is a URL rather than an object key. A URL changes whenever it is regenerated, which changes the document bytes, breaks canonicality, and turns the equality-based change check into a source of phantom sync conflicts. Store the object key and resolve it at render time."
        case .blockAttributeOnImageTerminator(let i, let name):
            "The newline terminating the image at op \(i) carries \"\(name)\". An image cannot be a header or a list item: segmentation drops that newline and reassembles a plain one, so the attribute would be silently lost."
        case .documentDoesNotEndWithNewline:
            "The document does not end with a newline. Quill terminates every document with one."
        case .emptyTextInsert(let i):
            "Op \(i) inserts an empty string, which carries no content and is never canonical."
        case .mergeFieldNotEnabled(let i):
            "Op \(i) is a mergeField embed, which is a P10 spike shape and not part of the authorable vocabulary."
        }
    }
}

extension Delta {
    /// Checks the document against the vocabulary and the structural rules the renderer,
    /// codec, and segmentation all assume hold.
    ///
    /// Returns every violation rather than throwing on the first, because when a fixture
    /// or a client is wrong it is far more useful to see the whole list at once.
    ///
    /// - Parameter allowingMergeFields: `mergeField` embeds are a P10 feasibility spike,
    ///   not something a client may author, so they are rejected unless explicitly allowed.
    public func vocabularyViolations(allowingMergeFields: Bool = false) -> [VocabularyViolation] {
        var violations: [VocabularyViolation] = []

        for (index, op) in ops.enumerated() {
            switch op.insert {
            case .text(let string):
                if string.isEmpty {
                    violations.append(.emptyTextInsert(index: index))
                }
            case .embed(let embed):
                if case .mergeField = embed, !allowingMergeFields {
                    violations.append(.mergeFieldNotEnabled(index: index))
                }
                // An image op must be immediately followed by a newline insert. This is what
                // makes images block-level, and the segmentation logic depends on it: split
                // drops exactly one newline after an image, and reassemble puts exactly one
                // back. If an image could sit between two text runs on a line, that pairing
                // would not be well-defined.
                if case .image(let key) = embed, Self.looksLikeURL(key) {
                    violations.append(.imageReferenceIsURL(index: index, value: key))
                }
                if case .image = embed {
                    // The other half of "block-level only": an image must start its own line
                    // as well as end it. Without this a document could put text and an image
                    // on one line, which segmentation has no way to represent — a text
                    // segment always ends at the image boundary.
                    if index > 0, !ops[index - 1].textContent.hasSuffix("\n") {
                        violations.append(.imageNotPrecededByNewline(index: index))
                    }
                    let next = index + 1 < ops.count ? ops[index + 1] : nil
                    let followedByNewline = next?.textContent.hasPrefix("\n") ?? false
                    if !followedByNewline {
                        violations.append(.imageNotFollowedByNewline(index: index))
                    } else if let terminatorAttributes = next?.attributes {
                        // Found while writing the fixture corpus, and not stated in the PRD:
                        // the newline that terminates an image must be bare. Split drops it
                        // and reassemble emits a plain "\n" in its place, so a header or list
                        // attribute riding on it would vanish on the first native edit — a
                        // silent content loss of exactly the kind P6 exists to rule out.
                        // An image therefore cannot itself be a list item or a heading.
                        for name in terminatorAttributes.keys.sorted()
                        where Vocabulary.blockAttributes.contains(name) {
                            violations.append(.blockAttributeOnImageTerminator(index: index, name: name))
                        }
                    }
                }
            }

            guard let attributes = op.attributes else { continue }
            for (name, value) in attributes {
                violations.append(contentsOf: check(name: name, value: value, on: op, at: index))
            }
        }

        if ops.last?.textContent.hasSuffix("\n") != true {
            violations.append(.documentDoesNotEndWithNewline)
        }

        return violations
    }

    /// Narrow on purpose. The rule is **not** "no URLs in a Delta" — `link` attributes are
    /// legitimately URLs and must survive. It is specifically that an *image embed's value* is
    /// an object key.
    static func looksLikeURL(_ value: String) -> Bool {
        guard let range = value.range(of: "://") else {
            return value.lowercased().hasPrefix("data:")
        }
        // A scheme is letters, digits, +, -, . and must not contain a path separator.
        let scheme = value[value.startIndex..<range.lowerBound]
        return !scheme.isEmpty && !scheme.contains("/")
            && scheme.allSatisfy { $0.isLetter || $0.isNumber || "+-.".contains($0) }
    }

    public var isWithinVocabulary: Bool {
        vocabularyViolations().isEmpty
    }

    private func check(
        name: String,
        value: AttributeValue,
        on op: Op,
        at index: Int
    ) -> [VocabularyViolation] {
        if op.isEmbed {
            guard Vocabulary.embedAttributes.contains(name) else {
                return [Vocabulary.inlineAttributes.contains(name) || Vocabulary.blockAttributes.contains(name)
                    ? .inlineAttributeOnEmbed(index: index, name: name)
                    : .unknownAttribute(index: index, name: name)]
            }
            guard case .string = value else { return [.wrongAttributeType(index: index, name: name)] }
            return []
        }

        let text = op.textContent

        if Vocabulary.blockAttributes.contains(name) {
            // A block attribute must sit on a run that is newlines only, because it
            // describes the line those newlines terminate. And it must be a single
            // newline: a run of "\n\n" carrying header:1 cannot say which of the two
            // lines is the header, so the canonical form always splits them.
            guard !text.isEmpty, text.allSatisfy({ $0 == "\n" }) else {
                return [.blockAttributeOnNonNewline(index: index, name: name)]
            }
            guard text.count == 1 else {
                return [.attributeOnMultiCharacterNewlineRun(index: index, name: name)]
            }
            switch (name, value) {
            case ("header", .int(let level)):
                return Vocabulary.headerLevels.contains(level) ? [] : [.headerLevelOutOfRange(index: index, level: level)]
            case ("list", .string(let kind)):
                return Vocabulary.listKinds.contains(kind) ? [] : [.unknownListKind(index: index, kind: kind)]
            default:
                return [.wrongAttributeType(index: index, name: name)]
            }
        }

        if Vocabulary.inlineAttributes.contains(name) {
            // An inline mark may not ride on a run that contains a newline. Encode assigns
            // newline characters their block attributes and nothing else, so a mark here
            // would be silently dropped and the document would not round-trip.
            if text.contains("\n") {
                return [.inlineAttributeOnNewlineRun(index: index, name: name)]
            }
            switch (name, value) {
            case ("link", .string):
                return []
            case ("bold", .bool), ("italic", .bool), ("underline", .bool), ("strike", .bool):
                return []
            default:
                return [.wrongAttributeType(index: index, name: name)]
            }
        }

        return [.unknownAttribute(index: index, name: name)]
    }
}
