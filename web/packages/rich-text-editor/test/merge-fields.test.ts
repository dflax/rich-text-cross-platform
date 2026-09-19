// @vitest-environment jsdom
import { describe, expect, test } from "vitest";

import { decodeDelta } from "../src/delta";
import { quillOptions, registerBlots } from "../src/quill-setup";
import { isWithinVocabulary, vocabularyViolations } from "../src/vocabulary";

/**
 * `mergeField` is not part of the vocabulary by default — a document type must opt in via
 * `allowMergeFields`/`allowingMergeFields` before it is authorable. These tests exercise
 * that opt-in against a real Quill instance, the same way `paste-guards.test.ts` does,
 * rather than only against hand-rolled Deltas: the thing that matters is what a host's own
 * `quill.insertEmbed(index, "mergeField", name)` call actually produces and whether Quill's
 * own `formats` allowlist lets it survive, not just whether our own decoder accepts the
 * shape in isolation.
 */
async function makeQuill(allowMergeFields: boolean) {
  const { default: Quill } = await import("quill");
  registerBlots(Quill);

  const container = document.createElement("div");
  document.body.appendChild(container);
  const editorNode = document.createElement("div");
  container.appendChild(editorNode);

  const quill = new Quill(editorNode, quillOptions({ toolbar: false, allowMergeFields }) as never);
  quill.setContents({ ops: [{ insert: "Dear , welcome.\n" }] } as never, "silent");
  return quill;
}

describe("mergeField authoring opt-in", () => {
  test("insertEmbed is preserved when allowMergeFields is true", async () => {
    const quill = await makeQuill(true);
    quill.insertEmbed(5, "mergeField", "viewer.firstName", "silent");

    const ops = quill.getContents().ops;
    const embedOp = ops.find((op) => typeof op.insert === "object" && op.insert !== null && "mergeField" in op.insert);
    expect(embedOp).toBeDefined();
    expect((embedOp!.insert as { mergeField: string }).mergeField).toBe("viewer.firstName");
  });

  test("insertEmbed throws when allowMergeFields is false, since mergeField is outside this instance's formats", async () => {
    // Quill derives a per-instance blot registry from `formats` (this is the actual
    // enforcement mechanism `ALLOWED_FORMATS`/`RENDER_FORMATS` rely on) — a name excluded
    // from it isn't silently ignored, it throws. A host gating its own insert-field
    // control on `allowMergeFields` never reaches this; this pins down what happens if
    // that gate is ever bypassed, so the failure mode is a loud one, not silent data loss.
    const quill = await makeQuill(false);
    expect(() => quill.insertEmbed(5, "mergeField", "viewer.firstName", "silent")).toThrow(/mergeField/);
  });

  test("the rendered pill is a non-editable, visually distinct span carrying the field name", async () => {
    const quill = await makeQuill(true);
    quill.insertEmbed(5, "mergeField", "viewer.firstName", "silent");

    const span = quill.root.querySelector(".merge-field") as HTMLElement | null;
    expect(span).not.toBeNull();
    expect(span!.getAttribute("contenteditable")).toBe("false");
    expect(span!.getAttribute("data-field")).toBe("viewer.firstName");
    // Quill's Embed blot wraps rendered content with zero-width non-breaking spaces
    // (U+FEFF) before/after, as cursor anchors either side of the embed — a real,
    // expected DOM detail of how any Embed blot renders, not specific to this one.
    expect(span!.textContent).toContain("viewer.firstName");
    expect(span!.style.borderRadius).not.toBe("");
    expect(span!.style.backgroundColor).not.toBe("");
  });

  test("a document containing a mergeField op decodes and round-trips through our own strict decoder", async () => {
    const quill = await makeQuill(true);
    quill.insertEmbed(5, "mergeField", "viewer.firstName", "silent");

    const json = JSON.stringify({ ops: quill.getContents().ops });
    const delta = decodeDelta(json);
    expect(isWithinVocabulary(delta, { allowingMergeFields: true })).toBe(true);
    expect(isWithinVocabulary(delta)).toBe(false);
    const violations = vocabularyViolations(delta);
    expect(violations.some((v) => v.kind === "mergeFieldNotEnabled")).toBe(true);
  });
});
