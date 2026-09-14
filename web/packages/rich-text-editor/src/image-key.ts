/**
 * Resolves a Delta image op's object key to a fetchable URL, and validates that a value
 * heading into an image op is a plausible key rather than a URL or a base64 blob.
 *
 * A URL is NEVER written into a Delta — only the key (see docs/backends/README.md's "Images"
 * row). Resolving happens here, at render time, against whatever base URL the host configures —
 * this file has no opinion about which object store that is.
 */

let baseURL: string | null = null;

/** Call once, before rendering any document, with wherever your images are publicly readable. */
export function configureImageBaseURL(url: string): void {
  baseURL = url.endsWith("/") ? url : url + "/";
}

/**
 * Resolves an object key to a fetchable URL. Throws if `configureImageBaseURL` was never
 * called — a silently-broken image is worse than a loud failure at setup time.
 */
export function resolveImageURL(key: string): string {
  if (!baseURL) {
    throw new Error(
      "resolveImageURL called before configureImageBaseURL — call it once at app startup with your image bucket/CDN's public base URL."
    );
  }
  return baseURL + key.split("/").map(encodeURIComponent).join("/");
}

/**
 * Whether a value is a plausible storage key rather than a URL or a base64 blob.
 *
 * This is the gate that keeps base64 out of the document. Quill's built-in image handling
 * base64-inlines dropped and pasted images straight into the Delta; a blob like that in a
 * `jsonb`/`json` column would destroy canonicality, and it's exactly the kind of thing that
 * looks fine until a document is a megabyte wide.
 */
export function isStorageKey(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    value.length < 512 &&
    !value.includes(":") && // rules out data:, http:, https:, blob:
    !value.startsWith("//") &&
    !value.startsWith("/") &&
    !value.includes("..")
  );
}
