// @vitest-environment jsdom
import { describe, expect, test } from "vitest";

import { decodeDelta } from "../src/delta";
import { installPasteGuards, registerBlots, ALLOWED_FORMATS } from "../src/quill-setup";

/**
 * installPasteGuards drops every pasted <img>, so a pasted image can never reach the
 * buffer as a foreign URL/blob embed. Exercised against a real Quill instance (not a
 * hand-rolled Delta) because the bug this guards against was a real Quill clipboard
 * behavior, not something a unit test against our own code would ever have caught: a
 * HEIC photo pasted from Notes.app on macOS produces a browser blob: URL that Quill's
 * default image matching turns into a non-string embed value ({"insert":{"image":true}}),
 * which the strict decoder then rejects -- confirmed against a real captured paste (see
 * CHANGELOG). Without the guard, this test fails the same way that crash did.
 */
async function makeQuill() {
  const { default: Quill } = await import("quill");
  registerBlots(Quill);

  const container = document.createElement("div");
  document.body.appendChild(container);
  const editorNode = document.createElement("div");
  container.appendChild(editorNode);

  const quill = new Quill(editorNode, {
    theme: "snow",
    formats: ALLOWED_FORMATS,
    modules: { toolbar: false, keyboard: true },
  } as never);
  installPasteGuards(quill);
  quill.setContents({ ops: [{ insert: "\n" }] } as never, "silent");
  return quill;
}

describe("installPasteGuards", () => {
  test("drops a pasted image whose src Quill's own matching can't resolve to a string", async () => {
    const quill = await makeQuill();
    // The exact shape captured from a real Notes.app HEIC-attachment paste: a blob: URL
    // src, which is what triggered "Op N's insert is neither a string nor an embed object".
    const html =
      '<p>A photograph</p><p><img src="blob:http://localhost:3000/c2982448-87a1-4b9a-b103-959cb21a7238" alt="IMG_2598.heic"></p><p>After</p>';
    const delta = quill.getModule("clipboard").convert({ html, text: "" });

    for (const op of delta.ops) {
      expect(typeof op.insert === "object" && op.insert !== null && "image" in op.insert).toBe(false);
    }
    // The whole document still decodes cleanly through the real strict decoder -- this
    // is what actually failed before the fix.
    expect(() => decodeDelta(JSON.stringify({ ops: delta.ops }))).not.toThrow();
  });

  test("drops a normally-pasted image with an ordinary URL too", async () => {
    const quill = await makeQuill();
    const html = '<p>Before</p><p><img src="https://example.com/photo.jpg" alt="a photo"></p><p>After</p>';
    const delta = quill.getModule("clipboard").convert({ html, text: "" });

    for (const op of delta.ops) {
      expect(typeof op.insert === "object" && op.insert !== null && "image" in op.insert).toBe(false);
    }
  });
});
