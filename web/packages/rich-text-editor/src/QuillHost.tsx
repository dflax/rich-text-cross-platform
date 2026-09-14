"use client";

/**
 * The one place Quill is constructed. Everything else (editor, corpus page, round-trip
 * page) goes through this so the constrained configuration cannot drift between them.
 *
 * Quill is imported dynamically because it touches `document` at module scope and would
 * break server rendering.
 */

import { useEffect, useRef, useState } from "react";
import type QuillType from "quill";

import { type Delta, fromParsedJSON } from "./delta";
import { quillOptions, registerBlots, type QuillOptions } from "./quill-setup";

export interface QuillHostProps extends QuillOptions {
  /** Loaded with `setContents`. Changing it reloads the editor. */
  initialDelta: Delta;
  /** Called once Quill is live, with a getter for the current contents. */
  onReady?: (api: QuillHostAPI) => void;
  className?: string;
}

export interface QuillHostAPI {
  quill: QuillType;
  /** `getContents()`, decoded through the strict decoder into our own Delta shape. */
  getDelta: () => Delta;
  setDelta: (delta: Delta) => void;
}

/**
 * Quill's `getContents()` returns a `quill-delta` instance whose ops are plain objects
 * but which may carry `attributes: {}` and other shapes our strict decoder has opinions
 * about. Round-tripping through JSON puts it on exactly the same footing as a document
 * arriving from the database, which is the comparison that matters.
 */
export function deltaFromQuill(quill: QuillType): Delta {
  return fromParsedJSON(JSON.parse(JSON.stringify({ ops: quill.getContents().ops })));
}

export default function QuillHost({
  initialDelta,
  onReady,
  className,
  readOnly = false,
  toolbar,
  allowMergeFields = false,
}: QuillHostProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const onReadyRef = useRef(onReady);
  onReadyRef.current = onReady;
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    let cancelled = false;
    let quill: QuillType | null = null;

    (async () => {
      const Quill = (await import("quill")).default;
      if (cancelled || !containerRef.current) return;
      registerBlots(Quill);

      // Rebuild from scratch on every load so a re-render cannot leave two toolbars or a
      // stale document behind.
      containerRef.current.innerHTML = "";
      const editorNode = document.createElement("div");
      containerRef.current.appendChild(editorNode);

      try {
        quill = new Quill(editorNode, quillOptions({ readOnly, toolbar, allowMergeFields }) as never);
        quill.setContents(initialDelta as never, "silent");
        onReadyRef.current?.({
          quill,
          getDelta: () => deltaFromQuill(quill!),
          setDelta: (delta) => quill!.setContents(delta as never, "silent"),
        });
      } catch (e) {
        setError((e as Error).message);
      }
    })();

    return () => {
      cancelled = true;
      if (container) container.innerHTML = "";
    };
  }, [initialDelta, readOnly, toolbar, allowMergeFields]);

  if (error) {
    return <p className="error">Quill failed to initialise: {error}</p>;
  }
  return <div ref={containerRef} className={className} />;
}
