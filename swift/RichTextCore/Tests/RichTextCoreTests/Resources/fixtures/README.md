# Delta fixture corpus

Hand-authored canonical Delta documents. Both clients read **these exact bytes** — the Swift
tests via `FixtureCorpus`, and (from Build Order step 8) the web client. Two corpora that
drifted apart would let each platform pass its own tests while disagreeing with the other,
which is precisely the failure the cross-platform claim (P7) is supposed to rule out.

## The rules these files follow

Every file is stored in the POC's **canonical byte form**, and
`FixtureHygieneTests.fixturesAreCanonicalOnDisk` asserts it by re-encoding each one and
comparing bytes. That test is what makes "byte-identical" mean something concrete
everywhere else:

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
  `{"insert":"a\nb"}`, not two. In practice this means the newline that terminates an image
  merges with whatever plain text follows it — see `image-in-bulleted-region.json`.
  Asserted by `fixturesAreCoalesced`.

## What each fixture is for

| File | What it proves |
|---|---|
| `empty-document.json` | Quill's empty document — a single `\n`. The degenerate case everything must survive. |
| `blank-lines.json` | Consecutive newlines are separate lines, not one collapsed line. |
| `single-paragraph.json` | The simplest non-empty document. |
| `multi-paragraph.json` | Newline splitting across several lines in one op. |
| `inline-bold.json` | An inline mark applies to exactly its run, not the whole line. |
| `inline-all-marks.json` | All four inline toggles, separately and combined on one run. |
| `link-inside-bold.json` | Build Order step 3 names this case: two attributes on one run. |
| `headers.json` | Header 1 and 2, each carried on the terminating `\n`. |
| `bullet-list.json` | Bullet blocks. |
| `ordered-list.json` | Ordered blocks and their numbering. |
| `ordered-list-restart.json` | Numbering restarts after an interrupting paragraph — silently wrong output if handled badly. |
| `adjacent-identical-runs.json` | Long prose that `AttributedString` will internally split on attributes the codec ignores. Must re-encode as **one** op, not several. |
| `special-characters.json` | Pins the JSON escaper: quotes, backslash, forward slash, tab, emoji, non-ASCII. |
| `image-only.json` | A document that is nothing but an image. |
| `image-with-alt.json` | `alt` on the embed, which becomes the SwiftUI `accessibilityLabel`. |
| `leading-image.json` | Image first — segmentation must produce a leading empty text segment. |
| `trailing-image.json` | Image last — segmentation must produce a trailing empty text segment. |
| `adjacent-images.json` | Two images back to back, which produce an empty text segment between them. |
| `image-in-bulleted-region.json` | An image interrupting a bulleted list without joining it (see below). |
| `full-vocabulary.json` | Every element of the vocabulary in one document. The P1 side-by-side comparison target. |
| `spike/mergefield.json` | The P10 embed-feasibility shape. **Not** authorable — `vocabularyViolations()` rejects it unless `allowingMergeFields: true`. |

## A rule the PRD does not state

**An image's terminating newline must be bare.** It may not carry `header` or `list`.

Segmentation drops the newline that follows an image and reassembles a plain `"\n"` in its
place, so an attribute riding on that newline would vanish on the first native edit — a
silent content loss of exactly the kind P6 exists to rule out. The consequence is that
**an image cannot itself be a list item or a heading**; it interrupts a list rather than
joining it, which is what `image-in-bulleted-region.json` pins.

This is enforced by `VocabularyViolation.blockAttributeOnImageTerminator` and must be
enforced on the web side too when the Quill image handler is built (Build Order step 8) —
Quill will happily let a user make an image a list item otherwise.

## A second rule the PRD does not state

**Inline marks may not ride on a run containing a newline.** `{"insert":"\n","attributes":
{"bold":true}}` is rejected. Bold on a newline renders as nothing, Quill never emits it, and
the encoder assigns newline characters their block attributes and nothing else — so it would
be silently dropped. Enforced by `VocabularyViolation.inlineAttributeOnNewlineRun`.

## Adding a fixture

Author it by hand in canonical form, then run `swift test`. If the byte form is off,
`fixturesAreCanonicalOnDisk` prints both the on-disk and re-encoded strings; if the ops are
not merged, `fixturesAreCoalesced` prints the coalesced version. Either way the fix is
usually visible at a glance.

Do not generate fixtures with the encoder — hand-authoring is what makes those tests real
checks on the encoder rather than tautologies. Four of the fixtures here were initially wrong
in exactly the way `fixturesAreCoalesced` now catches, and the codec round-trip is what
found it.
