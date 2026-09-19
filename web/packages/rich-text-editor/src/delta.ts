/**
 * The JS twin of `apple/RichTextCore/Sources/RichTextCore/Delta.swift`.
 *
 * Every rule here exists because the Swift side already encodes it. The bar is
 * byte-identity: `canonicalJSON(decodeDelta(bytes))` must reproduce the exact bytes
 * the Swift encoder writes for the same document, or the cross-platform-consistency claim
 * this whole project rests on is meaningless. Read the Swift file alongside this one before changing anything.
 */

// MARK: - Attribute values

/**
 * The value side of a Delta attribute. The vocabulary only ever produces three
 * shapes: `true` for the inline toggles, a string for `link`/`alt`, and an integer
 * for `header`. Anything else is rejected at decode time rather than coerced.
 */
export type AttributeValue = boolean | string | number;

export type Attributes = Record<string, AttributeValue>;

// MARK: - Embeds

/**
 * Images are always authorable. `mergeField` is not part of the vocabulary by default —
 * a document type must explicitly opt in (see `vocabulary.ts`'s `allowingMergeFields` and
 * `quill-setup.ts`'s `allowMergeFields`) before a `mergeField` embed passes validation or
 * decodes for editing.
 */
export type Embed = { image: string } | { mergeField: string };

const EMBED_KEYS = ["image", "mergeField"] as const;
export type EmbedKey = (typeof EMBED_KEYS)[number];

export function embedKey(embed: Embed): EmbedKey {
  return "image" in embed ? "image" : "mergeField";
}

export function embedValue(embed: Embed): string {
  return "image" in embed ? embed.image : embed.mergeField;
}

export function isImageEmbed(embed: Embed): embed is { image: string } {
  return "image" in embed;
}

// MARK: - Op

/**
 * A single Delta operation. This library stores documents wholesale, never as diffs, so
 * `insert` is the only operation kind — `retain` and `delete` cannot appear.
 */
export interface Op {
  insert: string | Embed;
  /**
   * Empty and absent are the same thing; `makeOp` normalizes `{}` to `undefined`.
   * Without this, `{"insert":"a"}` and `{"insert":"a","attributes":{}}` would compare
   * unequal while representing identical content, which breaks the equality-based
   * change check the whole sync design rests on. Swift's `Op.init` does the same.
   */
  attributes?: Attributes;
}

export interface Delta {
  ops: Op[];
}

export function makeOp(insert: string | Embed, attributes?: Attributes | null): Op {
  if (attributes && Object.keys(attributes).length > 0) {
    return { insert, attributes };
  }
  return { insert };
}

export function isEmbedOp(op: Op): op is Op & { insert: Embed } {
  return typeof op.insert !== "string";
}

/** The text this op contributes to the plain-text projection. Embeds contribute nothing. */
export function opTextContent(op: Op): string {
  return typeof op.insert === "string" ? op.insert : "";
}

export const EMPTY_DELTA: Delta = { ops: [{ insert: "\n" }] };

export function plainText(delta: Delta): string {
  return delta.ops.map(opTextContent).join("");
}

/** Every image key referenced, in document order, deduplicated. */
export function imageKeys(delta: Delta): string[] {
  const seen = new Set<string>();
  const keys: string[] = [];
  for (const op of delta.ops) {
    if (typeof op.insert === "string" || !isImageEmbed(op.insert)) continue;
    if (seen.has(op.insert.image)) continue;
    seen.add(op.insert.image);
    keys.push(op.insert.image);
  }
  return keys;
}

// MARK: - Attribute comparison

/**
 * Deep equality over attribute maps. `===` on JS objects would never be true, which
 * would silently turn `coalesced()` into a no-op while every test still passed —
 * so this helper is load-bearing, not a convenience. Swift gets it for free from
 * `Dictionary: Equatable`.
 */
export function sameAttributes(a: Attributes | undefined, b: Attributes | undefined): boolean {
  const aKeys = a ? Object.keys(a) : [];
  const bKeys = b ? Object.keys(b) : [];
  if (aKeys.length !== bKeys.length) return false;
  for (const key of aKeys) {
    if (!b || !Object.prototype.hasOwnProperty.call(b, key)) return false;
    if (!Object.is(a![key], b[key])) return false;
  }
  return true;
}

// MARK: - Coalescing

/**
 * Merges adjacent text ops carrying identical attributes.
 *
 * This is what Quill's own `Delta.push` does, and it happens regardless of newlines:
 * `insert("a\n").insert("b")` is one op, `{"insert":"a\nb"}`, not two. Delta is meant
 * to be canonical — exactly one representation per document state.
 *
 * The canonical *encoder* deliberately does not do this: it stays faithful so the
 * round-trip tests can catch non-canonical output. Normalization is this separate step.
 */
export function coalesced(delta: Delta): Delta {
  const result: Op[] = [];
  for (const op of delta.ops) {
    const last = result[result.length - 1];
    if (
      typeof op.insert === "string" &&
      last !== undefined &&
      typeof last.insert === "string" &&
      sameAttributes(last.attributes, op.attributes)
    ) {
      result[result.length - 1] = makeOp(last.insert + op.insert, op.attributes);
      continue;
    }
    result.push(op);
  }
  return { ops: result };
}

/**
 * True when no two adjacent text ops share identical attributes. Note the asymmetry
 * with `coalesced()`: adjacent *embeds* are never uncoalesced, which mirrors Swift's
 * `isCoalesced`.
 */
export function isCoalesced(delta: Delta): boolean {
  for (let i = 1; i < delta.ops.length; i += 1) {
    const first = delta.ops[i - 1];
    const second = delta.ops[i];
    if (isEmbedOp(first) || isEmbedOp(second)) continue;
    if (sameAttributes(first.attributes, second.attributes)) return false;
  }
  return true;
}

// MARK: - Errors

export class DeltaError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DeltaError";
  }
}

// MARK: - Decoding

/**
 * Parses Delta JSON.
 *
 * Deliberately strict, matching Swift's decoder: anything it does not understand is
 * an error rather than a silently ignored op. A parser that skips what it cannot
 * represent loses content, and this format's whole point is that content is never lost.
 */
export function decodeDelta(json: string): Delta {
  let root: unknown;
  try {
    root = JSON.parse(json);
  } catch (error) {
    throw new DeltaError(`Delta JSON is not valid JSON: ${(error as Error).message}`);
  }
  return fromParsedJSON(root);
}

export function fromParsedJSON(root: unknown): Delta {
  if (typeof root !== "object" || root === null || Array.isArray(root)) {
    throw new DeltaError('Delta JSON must be an object with an "ops" array.');
  }
  const rawOps = (root as Record<string, unknown>)["ops"];
  if (!Array.isArray(rawOps)) {
    throw new DeltaError('Delta JSON is missing its "ops" array.');
  }

  const ops: Op[] = [];
  rawOps.forEach((rawOp, index) => {
    if (typeof rawOp !== "object" || rawOp === null || Array.isArray(rawOp)) {
      throw new DeltaError(`Op ${index} is not a JSON object.`);
    }
    const opObject = rawOp as Record<string, unknown>;
    if (opObject["retain"] !== undefined || opObject["delete"] !== undefined) {
      throw new DeltaError(`Op ${index} is a retain or delete. This library stores documents wholesale, never as diffs.`);
    }
    const rawInsert = opObject["insert"];
    if (rawInsert === undefined) {
      throw new DeltaError(`Op ${index} has no "insert" key.`);
    }

    let insert: string | Embed;
    if (typeof rawInsert === "string") {
      insert = rawInsert;
    } else if (typeof rawInsert === "object" && rawInsert !== null && !Array.isArray(rawInsert)) {
      const embedObject = rawInsert as Record<string, unknown>;
      const embedKeys = Object.keys(embedObject);
      if (embedKeys.length !== 1) {
        throw new DeltaError(`Op ${index}'s embed object has more than one key; an embed has exactly one.`);
      }
      const key = embedKeys[0];
      const value = embedObject[key];
      if (typeof value !== "string") {
        throw new DeltaError(`Op ${index}'s "insert" is neither a string nor an embed object.`);
      }
      if (key === "image") insert = { image: value };
      else if (key === "mergeField") insert = { mergeField: value };
      else throw new DeltaError(`Op ${index} is an embed of unknown type "${key}".`);
    } else {
      throw new DeltaError(`Op ${index}'s "insert" is neither a string nor an embed object.`);
    }

    let attributes: Attributes | undefined;
    const rawAttributes = opObject["attributes"];
    if (rawAttributes !== undefined) {
      if (typeof rawAttributes !== "object" || rawAttributes === null || Array.isArray(rawAttributes)) {
        throw new DeltaError(`Op ${index}'s "attributes" is not a JSON object.`);
      }
      const parsed: Attributes = {};
      for (const [name, value] of Object.entries(rawAttributes as Record<string, unknown>)) {
        if (typeof value === "boolean" || typeof value === "string") {
          parsed[name] = value;
        } else if (typeof value === "number" && Number.isInteger(value) && Number.isFinite(value)) {
          parsed[name] = value;
        } else {
          throw new DeltaError(
            `Op ${index}'s attribute "${name}" has a value that is not a bool, string, or integer.`,
          );
        }
      }
      attributes = parsed;
    }

    ops.push(makeOp(insert, attributes));
  });

  return { ops };
}

// MARK: - Canonical encoding

/**
 * A minimal, deterministic JSON string escaper.
 *
 * Hand-rolled rather than delegating to `JSON.stringify` because the exact escape set
 * has to match Swift's `jsonString` byte for byte, and `JSON.stringify` differs in two
 * ways that matter: for U+0008 and U+000C it emits the two-character escapes \b and
 * \f, where Swift's \u%04x fallback emits the six-character \u0008 and \u000c. (It
 * agrees on the more famous case - neither escapes / , which every doc-images/ key
 * depends on.)
 *
 * Iterating with `for...of` walks code points, matching Swift's `String.unicodeScalars`;
 * indexed iteration would split surrogate pairs.
 */
export function jsonString(value: string): string {
  let out = '"';
  for (const character of value) {
    switch (character) {
      case '"':
        out += '\\"';
        break;
      case "\\":
        out += "\\\\";
        break;
      case "\n":
        out += "\\n";
        break;
      case "\r":
        out += "\\r";
        break;
      case "\t":
        out += "\\t";
        break;
      default: {
        const codePoint = character.codePointAt(0)!;
        if (codePoint < 0x20) {
          out += "\\u" + codePoint.toString(16).padStart(4, "0");
        } else {
          out += character;
        }
      }
    }
  }
  return out + '"';
}

function encodeAttributeValue(value: AttributeValue): string {
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") return String(value);
  return jsonString(value);
}

function encodeOp(op: Op): string {
  let out = '{"insert":';
  if (typeof op.insert === "string") {
    out += jsonString(op.insert);
  } else {
    out += "{" + jsonString(embedKey(op.insert)) + ":" + jsonString(embedValue(op.insert)) + "}";
  }
  const attributes = op.attributes;
  if (attributes && Object.keys(attributes).length > 0) {
    out += ',"attributes":{';
    // Sorted so two Deltas with the same attributes always produce the same bytes.
    // Swift uses `keys.sorted()`, which for these ASCII names is the same order as
    // JS's default lexicographic sort over UTF-16 code units.
    const names = Object.keys(attributes).sort();
    names.forEach((name, index) => {
      if (index > 0) out += ",";
      out += jsonString(name) + ":" + encodeAttributeValue(attributes[name]);
    });
    out += "}";
  }
  return out + "}";
}

/**
 * Serializes to this library's canonical byte form — the same bytes `Delta.canonicalJSON()`
 * produces in Swift.
 *
 * Deliberately *faithful*, not normalizing: it emits exactly the ops it is given, in
 * order, without coalescing adjacent runs or dropping anything. That is what makes the
 * round-trip test able to catch non-canonical output.
 */
export function canonicalJSON(delta: Delta): string {
  let out = '{"ops":[';
  delta.ops.forEach((op, index) => {
    if (index > 0) out += ",";
    out += encodeOp(op);
  });
  return out + "]}";
}
