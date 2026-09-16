import { defineConfig } from "tsup";

// Producing a publishable dist/ — see docs/ROADMAP.md. ESM only (package.json already declares
// "type": "module"; nothing here needs CJS consumers). react/react-dom/quill are peerDependencies,
// not bundled — a consumer supplies their own copies, same reasoning as the peerDependencies
// entries themselves.
export default defineConfig({
  entry: ["src/index.ts"],
  format: ["esm"],
  dts: true,
  sourcemap: true,
  clean: true,
  external: ["react", "react-dom", "quill"],
});
