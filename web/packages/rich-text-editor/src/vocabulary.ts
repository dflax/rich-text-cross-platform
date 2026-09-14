/**
 * The JS twin of `apple/RichTextCore/Sources/RichTextCore/Vocabulary.swift`.
 *
 * Quill's `formats` allowlist filters attribute NAMES and nothing else. It cannot say
 * "header 3 is out of range", "this image may not be a list item", or "an image must
 * start its own line" — those are relationships between ops and between a name and its
 * value. Every one of them is silent content loss on the first native edit if it reaches
 * the database, so this module is the web client's real enforcement point and the
 * allowlist is only the first, coarse filter.
 *
 * Ported rule-for-rule from Swift rather than re-derived from the PRD: the Swift version
 * encodes three structural rules the PRD does not state (see fixtures/README.md).
 */

import {
  type Attributes,
  type AttributeValue,
  type Delta,
  type Op,
  isEmbedOp,
  isImageEmbed,
  opTextContent,
} from "./delta";

export const Vocabulary = {
  /** Attributes that live on a text run. */
  inlineAttributes: new Set(["bold", "italic", "underline", "strike", "link"]),
  /** Attributes that live on the `\n` terminating a line, not on the text run. */
  blockAttributes: new Set(["header", "list"]),
  /** Attributes permitted on an image embed. */
  embedAttributes: new Set(["alt"]),
  headerLevels: new Set([1, 2]),
  listKinds: new Set(["bullet", "ordered"]),
} as const;

/** The Quill `formats` allowlist — exactly the vocabulary table, plus the image embed. */
export const QUILL_FORMATS = ["bold", "italic", "underline", "strike", "link", "header", "list", "image"];

export type ViolationKind =
  | "unknownAttribute"
  | "wrongAttributeType"
  | "headerLevelOutOfRange"
  | "unknownListKind"
  | "blockAttributeOnNonNewline"
  | "inlineAttributeOnNewlineRun"
  | "inlineAttributeOnEmbed"
  | "attributeOnMultiCharacterNewlineRun"
  | "imageNotFollowedByNewline"
  | "imageNotPrecededByNewline"
  | "imageReferenceIsURL"
  | "blockAttributeOnImageTerminator"
  | "documentDoesNotEndWithNewline"
  | "emptyTextInsert"
  | "mergeFieldNotEnabled";

export interface VocabularyViolation {
  kind: ViolationKind;
  /** Op index, or -1 for the document-level rule. */
  index: number;
  description: string;
}

function violation(kind: ViolationKind, index: number, description: string): VocabularyViolation {
  return { kind, index, description };
}

/**
 * A stable identity for a violation, so two implementations can be compared as sets.
 * Swift iterates an unordered dictionary when checking an op's attributes, so its
 * violation *order* is not stable and must never be compared directly.
 */
export function violationKey(v: VocabularyViolation): string {
  return `${v.kind}@${v.index}:${v.description}`;
}

function checkAttribute(
  name: string,
  value: AttributeValue,
  op: Op,
  index: number,
): VocabularyViolation[] {
  if (isEmbedOp(op)) {
    if (!Vocabulary.embedAttributes.has(name)) {
      const isKnownElsewhere =
        Vocabulary.inlineAttributes.has(name) || Vocabulary.blockAttributes.has(name);
      return [
        isKnownElsewhere
          ? violation(
              "inlineAttributeOnEmbed",
              index,
              `Op ${index} is an embed carrying the inline attribute "${name}".`,
            )
          : violation(
              "unknownAttribute",
              index,
              `Op ${index} carries "${name}", which is not in the vocabulary.`,
            ),
      ];
    }
    if (typeof value !== "string") {
      return [
        violation(
          "wrongAttributeType",
          index,
          `Op ${index}'s "${name}" has the wrong value type for the vocabulary.`,
        ),
      ];
    }
    return [];
  }

  const text = opTextContent(op);

  if (Vocabulary.blockAttributes.has(name)) {
    // A block attribute must sit on a run that is newlines only, because it describes
    // the line those newlines terminate. And it must be a single newline: a run of
    // "\n\n" carrying header:1 cannot say which of the two lines is the header.
    if (text.length === 0 || [...text].some((c) => c !== "\n")) {
      return [
        violation(
          "blockAttributeOnNonNewline",
          index,
          `Op ${index} carries the block attribute "${name}" but is not a newline run. ` +
            `Block attributes attach to the \\n that terminates a line.`,
        ),
      ];
    }
    if (text.length !== 1) {
      return [
        violation(
          "attributeOnMultiCharacterNewlineRun",
          index,
          `Op ${index} carries the block attribute "${name}" but inserts more than one newline, ` +
            `so it is ambiguous which line the attribute terminates.`,
        ),
      ];
    }
    if (name === "header" && typeof value === "number") {
      return Vocabulary.headerLevels.has(value)
        ? []
        : [
            violation(
              "headerLevelOutOfRange",
              index,
              `Op ${index} has header level ${value}; the vocabulary allows only 1 and 2.`,
            ),
          ];
    }
    if (name === "list" && typeof value === "string") {
      return Vocabulary.listKinds.has(value)
        ? []
        : [
            violation(
              "unknownListKind",
              index,
              `Op ${index} has list kind "${value}"; the vocabulary allows only bullet and ordered.`,
            ),
          ];
    }
    return [
      violation(
        "wrongAttributeType",
        index,
        `Op ${index}'s "${name}" has the wrong value type for the vocabulary.`,
      ),
    ];
  }

  if (Vocabulary.inlineAttributes.has(name)) {
    // An inline mark may not ride on a run containing a newline. Encode assigns newline
    // characters their block attributes and nothing else, so a mark here would be
    // silently dropped and the document would not round-trip.
    if (text.includes("\n")) {
      return [
        violation(
          "inlineAttributeOnNewlineRun",
          index,
          `Op ${index} carries the inline attribute "${name}" on a run containing a newline. ` +
            `Inline marks render as nothing on a newline, Quill never emits them, and the codec ` +
            `drops them on encode - so this cannot round-trip.`,
        ),
      ];
    }
    if (name === "link" && typeof value === "string") return [];
    if (
      (name === "bold" || name === "italic" || name === "underline" || name === "strike") &&
      typeof value === "boolean"
    ) {
      return [];
    }
    return [
      violation(
        "wrongAttributeType",
        index,
        `Op ${index}'s "${name}" has the wrong value type for the vocabulary.`,
      ),
    ];
  }

  return [
    violation("unknownAttribute", index, `Op ${index} carries "${name}", which is not in the vocabulary.`),
  ];
}

/**
 * Narrow on purpose. The rule is **not** "no URLs in a Delta" - `link` attributes are
 * legitimately URLs and must survive (fixtures/link-inside-bold.json and
 * fixtures/full-vocabulary.json both contain real ones). It is specifically that an
 * *image embed's value* is an object key.
 *
 * Kept character-for-character in step with Swift's `Delta.looksLikeURL`.
 */
export function looksLikeURL(value: string): boolean {
  const at = value.indexOf("://");
  if (at === -1) return value.toLowerCase().startsWith("data:");
  // A scheme is letters, digits, +, -, . and must not contain a path separator.
  const scheme = value.slice(0, at);
  return scheme.length > 0 && /^[A-Za-z0-9+\-.]+$/.test(scheme);
}

export interface VocabularyOptions {
  /**
   * `mergeField` embeds are a P10 feasibility spike, not something a client may author,
   * so they are rejected unless explicitly allowed.
   */
  allowingMergeFields?: boolean;
}

/**
 * Checks the document against the vocabulary and the structural rules the renderer,
 * codec, and segmentation all assume hold.
 *
 * Returns every violation rather than throwing on the first, because when a document is
 * wrong it is far more useful to see the whole list at once.
 */
export function vocabularyViolations(delta: Delta, options: VocabularyOptions = {}): VocabularyViolation[] {
  const { allowingMergeFields = false } = options;
  const violations: VocabularyViolation[] = [];
  const ops = delta.ops;

  ops.forEach((op, index) => {
    if (typeof op.insert === "string") {
      if (op.insert.length === 0) {
        violations.push(
          violation(
            "emptyTextInsert",
            index,
            `Op ${index} inserts an empty string, which carries no content and is never canonical.`,
          ),
        );
      }
    } else {
      const embed = op.insert;
      if (!isImageEmbed(embed) && !allowingMergeFields) {
        violations.push(
          violation(
            "mergeFieldNotEnabled",
            index,
            `Op ${index} is a mergeField embed, which is a P10 spike shape and not part of the ` +
              `authorable vocabulary.`,
          ),
        );
      }
      if (isImageEmbed(embed) && looksLikeURL(embed.image)) {
        violations.push(
          violation(
            "imageReferenceIsURL",
            index,
            `The image at op ${index} references "${embed.image}", which is a URL rather than an ` +
              `object key. A URL changes whenever it is regenerated, which changes the document ` +
              `bytes, breaks canonicality, and turns the equality-based change check into a source ` +
              `of phantom sync conflicts. Store the object key and resolve it at render time.`,
          ),
        );
      }
      if (isImageEmbed(embed)) {
        // "Block-level only", first half: an image must start its own line. Without this
        // a document could put text and an image on one line, which segmentation has no
        // way to represent. Note there is no `index > 0` guard - an image at op 0 already
        // starts a line, which is why leading-image.json and image-only.json pass.
        if (index > 0 && !opTextContent(ops[index - 1]).endsWith("\n")) {
          violations.push(
            violation(
              "imageNotPrecededByNewline",
              index,
              `The image at op ${index} does not start a line. Images are block-level only: ` +
                `one may never sit between two text runs on the same line.`,
            ),
          );
        }
        // Second half: an image must be immediately followed by a newline insert. The
        // segmentation logic depends on it - split drops exactly one newline after an
        // image and reassemble puts exactly one back.
        const next = index + 1 < ops.length ? ops[index + 1] : undefined;
        const followedByNewline = next !== undefined && opTextContent(next).startsWith("\n");
        if (!followedByNewline) {
          violations.push(
            violation(
              "imageNotFollowedByNewline",
              index,
              `The image at op ${index} is not immediately followed by a newline insert. ` +
                `Images are block-level only.`,
            ),
          );
        } else if (next.attributes) {
          // Found while writing the fixture corpus, and not stated in the PRD: the newline
          // that terminates an image must be bare. Split drops it and reassemble emits a
          // plain "\n" in its place, so a header or list attribute riding on it would
          // vanish on the first native edit. An image therefore cannot itself be a list
          // item or a heading - and Quill permits exactly that by default, which is why
          // this check is the load-bearing one on the web side.
          for (const name of Object.keys(next.attributes).sort()) {
            if (!Vocabulary.blockAttributes.has(name)) continue;
            violations.push(
              violation(
                "blockAttributeOnImageTerminator",
                index,
                `The newline terminating the image at op ${index} carries "${name}". An image ` +
                  `cannot be a header or a list item: segmentation drops that newline and ` +
                  `reassembles a plain one, so the attribute would be silently lost.`,
              ),
            );
          }
        }
      }
    }

    const attributes: Attributes | undefined = op.attributes;
    if (!attributes) return;
    for (const [name, value] of Object.entries(attributes)) {
      violations.push(...checkAttribute(name, value, op, index));
    }
  });

  const last = ops[ops.length - 1];
  if (last === undefined || !opTextContent(last).endsWith("\n")) {
    violations.push(
      violation(
        "documentDoesNotEndWithNewline",
        -1,
        "The document does not end with a newline. Quill terminates every document with one.",
      ),
    );
  }

  return violations;
}

export function isWithinVocabulary(delta: Delta, options: VocabularyOptions = {}): boolean {
  return vocabularyViolations(delta, options).length === 0;
}

/**
 * Clamps attribute VALUES into the vocabulary, leaving content untouched.
 *
 * This exists because of something observed rather than assumed: Quill's `formats`
 * allowlist filters attribute NAMES only, so pasting an `<h3>` yields `{"header":3}` —
 * the name is allowed, the value is not. Same story for `<ul data-checked>`, which
 * yields `list: "checked"`.
 *
 * Applied ONLY on the paste path, never on a `text-change` handler: re-running
 * `setContents` while someone is typing destroys the cursor position.
 *
 * Deliberately lossy in the smallest possible way: a level-3+ heading becomes a level-2
 * heading and a checklist becomes a bullet list, rather than the whole line being
 * dropped. Content is never removed.
 */
export function clampToVocabulary(delta: Delta): Delta {
  return {
    ops: delta.ops.map((op) => {
      if (!op.attributes) return op;
      let changed = false;
      const next: Attributes = {};
      for (const [name, value] of Object.entries(op.attributes)) {
        if (name === "header" && typeof value === "number" && !Vocabulary.headerLevels.has(value)) {
          next[name] = value < 1 ? 1 : 2;
          changed = true;
        } else if (name === "list" && typeof value === "string" && !Vocabulary.listKinds.has(value)) {
          next[name] = "bullet";
          changed = true;
        } else {
          next[name] = value;
        }
      }
      return changed ? { ...op, attributes: next } : op;
    }),
  };
}
