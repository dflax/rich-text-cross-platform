import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";

import { canonicalJSON, decodeDelta } from "../src/delta";
import { isWithinVocabulary } from "../src/vocabulary";

/**
 * The same fixture corpus `swift/Tests/RichTextCoreTests` proves the Swift codec against,
 * shared at the repo root — this is what makes "the same document round-trips identically on
 * both platforms" a checked property rather than an assumption. See docs/ARCHITECTURE.md.
 *
 * NOTE (docs/ROADMAP.md): the Swift package keeps its own copy under
 * swift/Tests/RichTextCoreTests/Resources/fixtures for SPM resource-bundling reasons (a
 * standalone package's resources must live inside its own target directory). Keep the two
 * copies in sync until that's automated.
 */
const fixturesDir = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "..", "fixtures");

function loadFixtures(): { name: string; json: string }[] {
  return readdirSync(fixturesDir)
    .filter((name) => name.endsWith(".json"))
    .map((name) => ({
      name: name.replace(/\.json$/, ""),
      json: readFileSync(join(fixturesDir, name), "utf8").trim(),
    }));
}

describe("Round trip: canonicalJSON(decodeDelta(json)) === json", () => {
  const fixtures = loadFixtures();

  test("the corpus is present", () => {
    expect(fixtures.length).toBeGreaterThanOrEqual(15);
  });

  for (const fixture of fixtures) {
    test(`${fixture.name} round-trips byte-identically`, () => {
      const decoded = decodeDelta(fixture.json);
      expect(canonicalJSON(decoded)).toBe(fixture.json);
    });
  }

  test("every authorable fixture is within the shared vocabulary", () => {
    for (const fixture of fixtures) {
      const delta = decodeDelta(fixture.json);
      expect(isWithinVocabulary(delta), `${fixture.name} should be within the shared vocabulary`).toBe(true);
    }
  });
});
