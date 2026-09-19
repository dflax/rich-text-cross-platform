/**
 * Quill configuration and the custom image blot. Browser-only — import dynamically.
 *
 * Two enforcement points live here, and neither is optional:
 *
 * 1. The `formats` allowlist restricted to exactly the shared vocabulary (see
 *    docs/ARCHITECTURE.md). This is what strips out-of-vocabulary formats arriving via paste.
 *    It filters attribute NAMES only, which is why `vocabularyViolations()` still has to run
 *    before save — see vocabulary.ts.
 *
 * 2. A custom image blot. Quill's built-in behaviour base64-inlines dropped and pasted
 *    images straight into the Delta, and its `value()` returns the `src`, so a bare
 *    storage key would render as a broken relative URL. This blot keeps the key in
 *    `data-key` (which is what the Delta stores) and points `src` at the resolved public
 *    URL (which is what the browser renders, via `resolveImageURL` — see image-key.ts),
 *    and it refuses anything that is not a plausible storage key.
 */

import type QuillType from "quill";

import { isStorageKey, resolveImageURL } from "./image-key";

/**
 * Exactly the shared vocabulary (see docs/ARCHITECTURE.md), plus the image embed. Nothing else.
 *
 * `alt` is deliberately NOT here. It is not a registered Quill format — it is an
 * attribute of the image blot, produced by `StorageKeyImage.formats()` and consumed by
 * `.format()`. Listing it makes Quill log `Cannot register "alt" specified in "formats"
 * config`, and it round-trips correctly without being listed.
 */
export const ALLOWED_FORMATS = [
  "bold",
  "italic",
  "underline",
  "strike",
  "link",
  "header",
  "list",
  "image",
];

/** Header 1 and 2 only; bullet and ordered only. No other button exists. */
export const TOOLBAR = [
  ["bold", "italic", "underline", "strike"],
  ["link"],
  [{ header: 1 }, { header: 2 }],
  [{ list: "ordered" }, { list: "bullet" }],
  ["image"],
  ["clean"],
];

let registered = false;

/**
 * Registers the custom image blot. Idempotent — Quill's registry is global and React
 * strict mode mounts twice in development.
 */
export function registerBlots(Quill: typeof QuillType): void {
  if (registered) return;
  registered = true;

  const BaseImage = Quill.import("formats/image") as any;

  class StorageKeyImage extends BaseImage {
    // Deliberately an INLINE embed, matching the default and the fixture shape. Making
    // it a BlockEmbed would change how Quill emits the terminating newline and break
    // byte-identity against the corpus.
    static blotName = "image";
    static tagName = "IMG";

    static create(value: unknown) {
      // `super.create` is BaseImage's, which would set src from the raw value; we set
      // both attributes ourselves so the key and the URL never get confused.
      const node = document.createElement("img") as HTMLImageElement;
      if (isStorageKey(value)) {
        node.setAttribute("data-key", value);
        node.setAttribute("src", resolveImageURL(value));
      } else {
        // A URL or a base64 blob. Refused rather than adopted: there is no key to store,
        // and inlining the bytes would destroy canonicality. Rendered as a visible
        // placeholder so the failure is obvious rather than silent.
        node.setAttribute("data-key", "");
        node.setAttribute("data-rejected", String(value).slice(0, 64));
        node.setAttribute("alt", "Rejected image: not a storage key");
      }
      return node;
    }

    /** What lands in the Delta: the bare storage key, never a URL. */
    static value(domNode: HTMLElement) {
      return domNode.getAttribute("data-key") ?? "";
    }

    /**
     * `alt` only. The base blot also exposes `height` and `width`, which are outside the
     * vocabulary and would be a new round-trip failure mode (image sizing is
     * explicitly deferred -- see docs/ROADMAP.md).
     */
    static formats(domNode: HTMLElement) {
      const alt = domNode.getAttribute("alt");
      return alt ? { alt } : {};
    }

    format(name: string, value: unknown) {
      if (name === "alt") {
        if (value) this.domNode.setAttribute("alt", String(value));
        else this.domNode.removeAttribute("alt");
        return;
      }
      if (name === "height" || name === "width") return; // out of vocabulary, ignored
      super.format(name, value);
    }
  }

  Quill.register(StorageKeyImage, true);

  // A merge-field embed. Registered so `fixtures/spike/mergefield.json` can be RENDERED
  // (without a blot, Parchment throws "Unable to create mergeField blot" and the whole
  // document fails to load). It is deliberately NOT in ALLOWED_FORMATS, so a plain Quill
  // instance stays unauthorable by default: no toolbar button, no paste path, and
  // `vocabularyViolations()` still rejects it unless merge fields are explicitly allowed
  // (see `RENDER_FORMATS`/`allowMergeFields`) — exactly as on the Swift side.
  //
  // Styled with inline styles rather than a `.merge-field` class in an external
  // stylesheet: this package ships no CSS at all (the host owns Quill's theme CSS and
  // any of its own overrides), so a class-only treatment would render as unstyled,
  // invisible-boundary text unless every host remembered to add matching CSS. Inline
  // styles make the pill visually distinct out of the box, in both the read view and an
  // editor a host has opted into `allowMergeFields` for; `data-field`/`.merge-field` stay
  // for a host that does want to layer its own CSS on top.
  const Embed = Quill.import("blots/embed") as any;

  class MergeFieldBlot extends Embed {
    static blotName = "mergeField";
    static tagName = "SPAN";
    static className = "merge-field";

    static create(value: string) {
      const node = super.create(value) as HTMLElement;
      node.setAttribute("data-field", String(value));
      node.setAttribute("contenteditable", "false");
      node.textContent = String(value);
      node.style.cssText =
        "display:inline-block;padding:1px 8px;border-radius:9999px;" +
        "background-color:rgba(37,99,235,0.15);color:rgb(37,99,235);" +
        "font-size:0.875em;line-height:1.4;white-space:nowrap;";
      return node;
    }

    static value(domNode: HTMLElement) {
      return domNode.getAttribute("data-field") ?? "";
    }
  }

  Quill.register(MergeFieldBlot, true);
}

/**
 * The read-only allowlist. Same as `ALLOWED_FORMATS` plus the merge-field spike embed, so the
 * corpus page can render `spike/mergefield.json` without making merge fields authorable
 * anywhere. Mirrors Swift's `allowingMergeFields` flag.
 */
export const RENDER_FORMATS = [...ALLOWED_FORMATS, "mergeField"];

export interface QuillOptions {
  readOnly?: boolean;
  toolbar?: boolean;
  /**
   * Opts this Quill instance into the `mergeField` embed — both for rendering (the
   * read-only corpus/spike pages) and, when combined with `readOnly: false`, for
   * authoring: `formats` then includes `mergeField`, so a host's own imperative
   * `quill.insertEmbed(index, "mergeField", name)` call is accepted and preserved
   * instead of being silently dropped, and `vocabularyViolations({ allowingMergeFields:
   * true })` must be used to validate the result before save. `false` by default:
   * this is a narrow, document-type-specific capability, not a default part of the
   * vocabulary — a host should set this only on the specific document types (and the
   * specific Quill instance) it wants merge fields for, never as a blanket default.
   * There is still no toolbar button and no paste path for it either way — insertion is
   * always a deliberate, host-driven call, not something Quill offers on its own.
   */
  allowMergeFields?: boolean;
}

/**
 * Drops every pasted `<img>` from the incoming Delta entirely, before Quill's own image
 * matching runs on it. Call once per Quill instance (QuillHost does this for you).
 *
 * A pasted image can never become one of our storage-key embeds: a clipboard matcher
 * must return a Delta synchronously — there is no way to upload the pasted bytes and
 * patch the result back in mid-paste — and even when Quill's own image matching *can*
 * read a usable value off the node, that value is a foreign URL or blob, never one of
 * our keys; `vocabularyViolations()` would reject it on save anyway (see
 * `vocabulary.ts`'s `imageReferenceIsURL`). Some paste shapes Quill's own matching can't
 * even resolve to a string at all — observed with a HEIC photo pasted from Notes.app on
 * macOS, which the browser hands the page a `blob:` URL that Quill's default image
 * matching turns into a non-string embed value, corrupting the decoded delta ("Op N's
 * insert is neither a string nor an embed object"). Dropping every pasted `<img>` up
 * front sidesteps both failure modes the same way, and matches the Swift editor's own
 * documented behavior: "Pasted images are dropped entirely — this editor's images only
 * ever arrive through `RichTextImageUploading`" (`docs/guides/vocabulary-enforcement.md`).
 */
export function installPasteGuards(quill: QuillType): void {
  quill.clipboard.addMatcher("img", (_node, delta) => {
    const DeltaConstructor = delta.constructor as new () => typeof delta;
    return new DeltaConstructor();
  });
}

/**
 * The shared Quill options. `formats` is the allowlist; `modules.toolbar` offers exactly
 * the same set and nothing more.
 */
export function quillOptions(options: QuillOptions = {}) {
  const { readOnly = false, toolbar = !readOnly, allowMergeFields = false } = options;
  return {
    theme: "snow",
    readOnly,
    formats: allowMergeFields ? RENDER_FORMATS : ALLOWED_FORMATS,
    modules: {
      toolbar: toolbar ? TOOLBAR : false,
      // Quill's default keyboard bindings include code blocks and blockquote shortcuts.
      // Those formats are not in the allowlist, so the bindings are inert — verified by
      // the allowlist rather than by removing bindings one at a time.
      keyboard: true,
    },
  };
}
