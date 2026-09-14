import Foundation

// MARK: - Attribute values

/// The value side of a Delta attribute.
///
/// The vocabulary (see `Vocabulary`) only ever produces three shapes: `true` for the
/// inline toggles, a string for `link` and `alt`, and an integer for `header`. Anything
/// else is rejected at decode time rather than silently coerced — a silently-dropped
/// attribute is exactly the content-loss failure mode P6 exists to rule out.
public enum AttributeValue: Equatable, Hashable, Sendable {
    case bool(Bool)
    case string(String)
    case int(Int)
}

/// The block attributes of the line a newline terminates, carried as a single opaque value
/// rather than several separate ones. `NSDeltaCodec` tags it directly onto a paragraph's
/// terminating `\n` (see `.richTextBlockToken`) and reads it back verbatim on encode — headers
/// and lists are never *inferred* from a rendered font size or paragraph style, only restored
/// from this token, exactly as the vocabulary's own round-trip guarantee requires.
public struct BlockToken: Hashable, Sendable {
    public var attributes: [String: AttributeValue]

    public init(attributes: [String: AttributeValue]) {
        self.attributes = attributes
    }
}

// MARK: - Embeds

/// An `insert` whose value is an object rather than a string.
///
/// Images are the only embed in the shipped vocabulary. `mergeField` exists solely for
/// the P10 feasibility spike and is not part of the vocabulary a client may author.
public enum Embed: Equatable, Hashable, Sendable {
    case image(key: String)
    case mergeField(name: String)

    /// The single JSON key this embed serializes under.
    var jsonKey: String {
        switch self {
        case .image: "image"
        case .mergeField: "mergeField"
        }
    }

    var jsonValue: String {
        switch self {
        case .image(let key): key
        case .mergeField(let name): name
        }
    }
}

// MARK: - Op

/// A single Delta operation. This POC only ever stores documents, never diffs, so
/// `insert` is the only operation kind — `retain` and `delete` cannot appear.
public struct Op: Equatable, Hashable, Sendable {
    public enum Insert: Equatable, Hashable, Sendable {
        case text(String)
        case embed(Embed)
    }

    public var insert: Insert
    /// Empty and absent are the same thing and are normalized to `nil` on construction.
    /// Without this, `{"insert":"a"}` and `{"insert":"a","attributes":{}}` would compare
    /// unequal while representing identical content, which would break the equality-based
    /// change check the whole sync design rests on.
    public var attributes: [String: AttributeValue]?

    public init(insert: Insert, attributes: [String: AttributeValue]? = nil) {
        self.insert = insert
        self.attributes = (attributes?.isEmpty ?? true) ? nil : attributes
    }

    public static func text(_ string: String, _ attributes: [String: AttributeValue]? = nil) -> Op {
        Op(insert: .text(string), attributes: attributes)
    }

    public static func image(_ key: String, alt: String? = nil) -> Op {
        Op(insert: .embed(.image(key: key)), attributes: alt.map { ["alt": .string($0)] })
    }

    /// The text this op contributes to a document's plain-text projection. Embeds
    /// contribute nothing.
    public var textContent: String {
        switch insert {
        case .text(let string): string
        case .embed: ""
        }
    }

    public var isEmbed: Bool {
        if case .embed = insert { return true }
        return false
    }
}

// MARK: - Delta

/// A whole document: an ordered list of insert ops.
public struct Delta: Equatable, Hashable, Sendable {
    public var ops: [Op]

    public init(ops: [Op]) {
        self.ops = ops
    }

    /// The document Quill produces for empty content, and the default for a new row.
    public static let empty = Delta(ops: [.text("\n")])

    /// The plain-text projection stored alongside the Delta so list rows, search, and
    /// Spotlight never have to decode a document. Derived, never authoritative.
    public var plainText: String {
        ops.map(\.textContent).joined()
    }

    /// Every image key referenced by this document, in document order, deduplicated.
    /// Used to drive `ImageStore` prefetch at sync time.
    public var imageKeys: [String] {
        var seen = Set<String>()
        var keys: [String] = []
        for op in ops {
            guard case .embed(.image(let key)) = op.insert, seen.insert(key).inserted else { continue }
            keys.append(key)
        }
        return keys
    }
}

// MARK: - Coalescing

extension Delta {
    /// Merges adjacent text ops that carry identical attributes.
    ///
    /// This is what Quill's own `Delta.push` does, and it happens regardless of newlines:
    /// `insert("a\n").insert("b")` is one op, `{"insert":"a\nb"}`, not two. Delta is meant to
    /// be canonical — exactly one representation per document state — and an uncoalesced
    /// document breaks that, which in turn breaks the equality-based change check the sync
    /// design depends on.
    ///
    /// The canonical *encoder* deliberately does not do this: it stays faithful so the
    /// round-trip tests can catch a codec that emits uncoalesced output. Normalization is
    /// this separate, explicit step.
    public func coalesced() -> Delta {
        var result: [Op] = []
        for op in ops {
            guard case .text(let text) = op.insert,
                  case .text(let previousText)? = result.last?.insert,
                  result.last?.attributes == op.attributes
            else {
                result.append(op)
                continue
            }
            result[result.count - 1] = Op(insert: .text(previousText + text), attributes: op.attributes)
        }
        return Delta(ops: result)
    }

    /// True when no two adjacent text ops share identical attributes.
    public var isCoalesced: Bool {
        zip(ops, ops.dropFirst()).allSatisfy { first, second in
            !(!first.isEmbed && !second.isEmbed && first.attributes == second.attributes)
        }
    }
}

// MARK: - Errors

public enum DeltaError: Error, Equatable, CustomStringConvertible {
    case notAnObject
    case missingOps
    case opNotAnObject(index: Int)
    case missingInsert(index: Int)
    case unsupportedInsert(index: Int)
    case unknownEmbed(index: Int, key: String)
    case embedHasMultipleKeys(index: Int)
    case attributesNotAnObject(index: Int)
    case unsupportedAttributeValue(index: Int, name: String)
    case retainOrDeleteNotSupported(index: Int)

    public var description: String {
        switch self {
        case .notAnObject:
            "Delta JSON must be an object with an \"ops\" array."
        case .missingOps:
            "Delta JSON is missing its \"ops\" array."
        case .opNotAnObject(let i):
            "Op \(i) is not a JSON object."
        case .missingInsert(let i):
            "Op \(i) has no \"insert\" key."
        case .unsupportedInsert(let i):
            "Op \(i)'s \"insert\" is neither a string nor an embed object."
        case .unknownEmbed(let i, let key):
            "Op \(i) is an embed of unknown type \"\(key)\"."
        case .embedHasMultipleKeys(let i):
            "Op \(i)'s embed object has more than one key; an embed has exactly one."
        case .attributesNotAnObject(let i):
            "Op \(i)'s \"attributes\" is not a JSON object."
        case .unsupportedAttributeValue(let i, let name):
            "Op \(i)'s attribute \"\(name)\" has a value that is not a bool, string, or integer."
        case .retainOrDeleteNotSupported(let i):
            "Op \(i) is a retain or delete. This POC stores documents, never diffs."
        }
    }
}

// MARK: - Decoding

extension Delta {
    /// Parses Delta JSON.
    ///
    /// Deliberately strict: anything it does not understand is an error rather than a
    /// silently ignored op. A parser that skips what it cannot represent loses content,
    /// and the whole point of P6 is that content is never lost.
    public static func decode(json data: Data) throws -> Delta {
        let root = try JSONSerialization.jsonObject(with: data, options: [])
        guard let object = root as? [String: Any] else { throw DeltaError.notAnObject }
        guard let rawOps = object["ops"] as? [Any] else { throw DeltaError.missingOps }

        var ops: [Op] = []
        ops.reserveCapacity(rawOps.count)

        for (index, rawOp) in rawOps.enumerated() {
            guard let opObject = rawOp as? [String: Any] else { throw DeltaError.opNotAnObject(index: index) }
            if opObject["retain"] != nil || opObject["delete"] != nil {
                throw DeltaError.retainOrDeleteNotSupported(index: index)
            }
            guard let rawInsert = opObject["insert"] else { throw DeltaError.missingInsert(index: index) }

            let insert: Op.Insert
            if let text = rawInsert as? String {
                insert = .text(text)
            } else if let embedObject = rawInsert as? [String: Any] {
                guard embedObject.count == 1, let (key, value) = embedObject.first else {
                    throw DeltaError.embedHasMultipleKeys(index: index)
                }
                guard let stringValue = value as? String else {
                    throw DeltaError.unsupportedInsert(index: index)
                }
                switch key {
                case "image": insert = .embed(.image(key: stringValue))
                case "mergeField": insert = .embed(.mergeField(name: stringValue))
                default: throw DeltaError.unknownEmbed(index: index, key: key)
                }
            } else {
                throw DeltaError.unsupportedInsert(index: index)
            }

            var attributes: [String: AttributeValue]?
            if let rawAttributes = opObject["attributes"] {
                guard let attributeObject = rawAttributes as? [String: Any] else {
                    throw DeltaError.attributesNotAnObject(index: index)
                }
                var parsed: [String: AttributeValue] = [:]
                for (name, value) in attributeObject {
                    parsed[name] = try Self.attributeValue(from: value, name: name, index: index)
                }
                attributes = parsed
            }

            ops.append(Op(insert: insert, attributes: attributes))
        }

        return Delta(ops: ops)
    }

    private static func attributeValue(from value: Any, name: String, index: Int) throws -> AttributeValue {
        // NSNumber bridges both booleans and integers, so the CFBoolean check has to come
        // first — otherwise `true` decodes as the integer 1 and re-encodes as `1`, which is
        // a byte difference that would fail the round-trip test for a non-obvious reason.
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            if let intValue = Int(exactly: number) {
                return .int(intValue)
            }
            throw DeltaError.unsupportedAttributeValue(index: index, name: name)
        }
        if let string = value as? String {
            return .string(string)
        }
        throw DeltaError.unsupportedAttributeValue(index: index, name: name)
    }
}

// MARK: - Canonical encoding

extension Delta {
    /// Serializes to the POC's canonical byte form.
    ///
    /// "Byte-identical" in the round-trip tests means these bytes. The encoder is
    /// deliberately *faithful*, not normalizing: it emits exactly the ops it is given, in
    /// order, without coalescing adjacent runs or dropping anything. That is what makes
    /// the round-trip test able to catch non-canonical output — if a codec emits two
    /// adjacent runs with identical attributes where the source had one, these bytes
    /// differ and the test fails, which is the entire point.
    ///
    /// Determinism comes from three choices: keys within an object are always written in a
    /// fixed order, there is no insignificant whitespace, and non-ASCII characters are left
    /// as UTF-8 rather than `\u`-escaped.
    public func canonicalJSON() -> Data {
        var out = String()
        out.reserveCapacity(ops.count * 48)
        out += "{\"ops\":["
        for (index, op) in ops.enumerated() {
            if index > 0 { out += "," }
            out += Self.encode(op)
        }
        out += "]}"
        return Data(out.utf8)
    }

    public func canonicalJSONString() -> String {
        String(decoding: canonicalJSON(), as: UTF8.self)
    }

    private static func encode(_ op: Op) -> String {
        var out = "{\"insert\":"
        switch op.insert {
        case .text(let string):
            out += jsonString(string)
        case .embed(let embed):
            out += "{" + jsonString(embed.jsonKey) + ":" + jsonString(embed.jsonValue) + "}"
        }
        if let attributes = op.attributes, !attributes.isEmpty {
            out += ",\"attributes\":{"
            // Sorted so two Deltas with the same attributes always produce the same bytes,
            // regardless of dictionary iteration order.
            for (index, name) in attributes.keys.sorted().enumerated() {
                if index > 0 { out += "," }
                out += jsonString(name) + ":" + encode(attributes[name]!)
            }
            out += "}"
        }
        out += "}"
        return out
    }

    private static func encode(_ value: AttributeValue) -> String {
        switch value {
        case .bool(let flag): flag ? "true" : "false"
        case .int(let number): String(number)
        case .string(let string): jsonString(string)
        }
    }

    /// A minimal, deterministic JSON string escaper.
    ///
    /// Hand-rolled rather than delegating to `JSONSerialization` because the exact escape
    /// set has to be pinned: `JSONSerialization` escapes forward slashes, which would make
    /// every image key containing a `/` encode differently from how the web client writes
    /// it, and a byte-comparison bar cannot tolerate that kind of ambiguity.
    private static func jsonString(_ value: String) -> String {
        var out = "\""
        out.reserveCapacity(value.utf8.count + 2)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}
