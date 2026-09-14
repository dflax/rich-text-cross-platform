# Delta fixture corpus

Hand-authored canonical Delta documents. Both the Swift package (`RichTextCoreTests` via
`FixtureCorpus`) and the web package (`test/round-trip.test.ts`) read **these exact bytes** — two
corpora that drifted apart would let each platform pass its own tests while disagreeing with the
other, which is precisely the failure the cross-platform-consistency claim this project rests on
is supposed to rule out. See `docs/ARCHITECTURE.md`.

## The rules these files follow

Every file is stored in this project's **canonical byte form**, and
`FixtureHygieneTests.fixturesAreCanonicalOnDisk` asserts it by re-encoding each one and comparing
bytes. That test is what makes "byte-identical" mean something concrete everywhere else:

- One line per file, no insignificant whitespace. (Files end with a trailing newline, as
  text files should; it is not part of the document.)
- Within an op, `insert` is written before `attributes`.
- Attribute keys are sorted alphabetically.
- Forward slashes are **not** escaped — image keys contain them, and `\/` vs `/` is a byte
  difference the web client would not reproduce.
- Newlines are `\n` only.
- Every document ends with a newline, and no op inserts an empty string.
- **Adjacent text ops with identical attributes are merged**, across newlines included.
  Quill's own `Delta.push` does this: `insert("a\n").insert("b")` is one op,
  `{"insert":"a\nb"}`, not two. Asserted by `fixturesAreCoalesced`.

## What each fixture is for

| File | What it proves |
|---|---|
| `empty-document.json` | Quill's empty document — a single `\n`. The degenerate case everything must survive. |
| `blank-lines.json` | Consecutive newlines are separate lines, not one collapsed line. |
| `single-paragraph.json` | The simplest non-empty document. |
| `multi-paragraph.json` | Newline splitting across several lines in one op. |
| `inline-bold.json` | An inline mark applies to exactly its run, not the whole line. |
| `inline-all-marks.json` | All four inline toggles, separately and combined on one run. |
| `link-inside-bold.json` | Two attributes on one run. |
| `headers.json` | Header 1 and 2, each carried on the terminating `\n`, restored exactly rather than inferred from a rendered font size — see `docs/ARCHITECTURE.md`. |
| `bullet-list.json` | Bullet blocks. |
| `ordered-list.json` | Ordered blocks and their numbering. |
| `ordered-list-restart.json` | Numbering restarts after an interrupting paragraph — silently wrong output if handled badly. |
| `adjacent-identical-runs.json` | Long prose that a naive attributed-string decode will internally split on attributes the codec ignores. Must re-encode as **one** op, not several. |
| `special-characters.json` | Pins the JSON escaper: quotes, backslash, forward slash, tab, emoji, non-ASCII. |
| `image-only.json` | A document that is nothing but an image. |
| `image-with-alt.json` | `alt` on the embed, which becomes the accessibility label wherever the document is read. |
| `leading-image.json` | An image as the very first element in the document. |
| `trailing-image.json` | An image as the very last element in the document. |
| `adjacent-images.json` | Two images back to back, with nothing but a bare newline between them. |
| `image-in-bulleted-region.json` | An image interrupting a bulleted list without joining it (see below). |
| `full-vocabulary.json` | Every element of the shared vocabulary in one document. |
| `spike/mergefield.json` | A read-path-only embed feasibility shape. **Not** authorable — `vocabularyViolations()` rejects it unless `allowingMergeFields: true`. Excluded from `FixtureCorpus.all`. |

## Two rules worth stating explicitly

**An image's terminating newline must be bare — it may not carry `header` or `list`.** The
consequence: **an image cannot itself be a list item or a heading**; it interrupts a list rather
than joining it, which is what `image-in-bulleted-region.json` pins. Enforced by
`VocabularyViolation.blockAttributeOnImageTerminator` — and needs the equivalent enforcement on
the web side wherever a Quill image handler is built, since Quill will otherwise happily let a
user make an image a list item.

**Inline marks may not ride on a run containing a newline.** `{"insert":"\n","attributes":
{"bold":true}}` is rejected — bold on a bare newline renders as nothing, Quill never emits it,
and a run like that would be silently dropped on encode otherwise. Enforced by
`VocabularyViolation.inlineAttributeOnNewlineRun`.

## Adding a fixture

Author it by hand in canonical form, then run `swift test`. If the byte form is off,
`fixturesAreCanonicalOnDisk` prints both the on-disk and re-encoded strings; if the ops are
not merged, `fixturesAreCoalesced` prints the coalesced version. Either way the fix is
usually visible at a glance.

Do not generate fixtures with the encoder — hand-authoring is what makes those tests real
checks on the encoder rather than tautologies.
