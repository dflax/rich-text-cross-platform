import Foundation
import Testing
@testable import RichTextCore

/// Loads the shared Delta fixture corpus, bundled as a test-target resource (`Resources/fixtures`)
/// rather than located by walking up from `#filePath` to a sibling directory — the fork-point
/// POC repo could get away with the latter because the fixtures were shared with a co-located
/// web client at a known repo-root path; a standalone package can't assume anything about what
/// sits above it, so the corpus travels inside the package instead. See `PROVENANCE.md` for
/// where this corpus originally came from.
enum FixtureCorpus {
    static let directory: URL = Bundle.module.resourceURL!.appending(path: "fixtures")

    struct Fixture {
        let name: String
        let url: URL
        /// The file's bytes with trailing whitespace removed. Fixture files end with a
        /// newline the way text files should; that newline is not part of the document.
        let canonicalBytes: Data
        let delta: Delta

        var json: String { String(decoding: canonicalBytes, as: UTF8.self) }
    }

    /// Every fixture a client may legitimately author. Excludes `spike/`, which holds a
    /// read-path-only embed shape — not part of the authorable vocabulary.
    static var all: [Fixture] { load(in: directory) }

    static var spike: [Fixture] { load(in: directory.appending(path: "spike")) }

    static func named(_ name: String) throws -> Fixture {
        guard let fixture = all.first(where: { $0.name == name }) else {
            throw FixtureError.notFound(name)
        }
        return fixture
    }

    private static func load(in directory: URL) -> [Fixture] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let raw = try? Data(contentsOf: url) else { return nil }
                let trimmed = Data(
                    String(decoding: raw, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .utf8
                )
                guard let delta = try? Delta.decode(json: trimmed) else {
                    Issue.record("Fixture \(url.lastPathComponent) is not decodable Delta JSON.")
                    return nil
                }
                return Fixture(
                    name: url.deletingPathExtension().lastPathComponent,
                    url: url,
                    canonicalBytes: trimmed,
                    delta: delta
                )
            }
    }

    enum FixtureError: Error { case notFound(String) }
}
