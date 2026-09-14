import CryptoKit
import Foundation

/// Where image bytes come from when they are not already on disk.
///
/// Abstracted so `ImageStore` can be built and tested against a local fixture directory with
/// no network, then pointed at the real bucket without changing the caching logic — which is
/// the part that actually has to be right for the offline guarantee (P8).
public protocol ImageFetching: Sendable {
    func data(for key: String) async throws -> Data
}

/// Fetches an object key from any HTTP(S) endpoint that serves it as a plain, unauthenticated
/// GET — a public bucket on Backblaze B2, S3, Firebase Storage, a CDN in front of any of those,
/// or a self-hosted static file server. `RichTextCore` intentionally has no opinion about which:
/// this type is the entire integration surface, and a backend needing real authorization (a
/// signed URL, a bearer token) is expected to wrap or replace it with its own `ImageFetching`
/// conformance rather than have one baked in here. See `docs/backends/` for worked examples.
public struct PublicURLImageFetcher: ImageFetching {
    /// The endpoint an object key is appended to, e.g. `https://f005.backblazeb2.com/file/<bucket>`
    /// or `https://<bucket>.s3.<region>.amazonaws.com`.
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func data(for key: String) async throws -> Data {
        // `appending(path:)` percent-encodes each component but leaves the separators, which is
        // what object keys containing "/" need.
        let url = baseURL.appending(path: key)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw ImageStoreError.fetchFailed(key: key, statusCode: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ImageStoreError.fetchFailed(key: key, statusCode: http.statusCode)
        }
        return data
    }
}

/// Reads from a directory on disk. Used by tests, and by anything that wants to exercise the
/// cache with no network at all.
public struct LocalDirectoryImageFetcher: ImageFetching {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func data(for key: String) async throws -> Data {
        let url = directory.appending(path: key.replacingOccurrences(of: "/", with: "_"))
        guard let data = try? Data(contentsOf: url) else {
            throw ImageStoreError.fetchFailed(key: key, statusCode: 404)
        }
        return data
    }
}

public enum ImageStoreError: Error, Equatable, CustomStringConvertible {
    case fetchFailed(key: String, statusCode: Int?)

    public var description: String {
        switch self {
        case .fetchFailed(let key, let status):
            "Could not fetch image \"\(key)\"\(status.map { " (HTTP \($0))" } ?? "")."
        }
    }
}

/// A file-backed image cache that makes offline reads work.
///
/// Four details here are correctness rather than polish, and each has a specific failure it
/// prevents:
///
/// - Files live in **Application Support, not Caches.** The system may purge Caches at any
///   time, which would silently break the offline guarantee P8 tests — a document that
///   rendered yesterday would come back with holes today, with nothing in the app to explain
///   why.
/// - Filenames are the **SHA-256 of the object key**, so a key containing `/` (routine for an
///   object-storage key, e.g. `doc-images/…`) cannot be mistaken for a subdirectory path.
/// - The directory is marked **excluded from backup**, so cached image data does not bloat
///   iCloud backups.
/// - Writes are **atomic** — download to a temp file, then move — so an interrupted fetch can
///   never leave a truncated file that later looks like a valid cache hit.
public actor ImageStore {
    public let directory: URL
    private let fetcher: ImageFetching
    /// Coalesces concurrent requests for the same key. Without it, a view appearing while a
    /// sync-time prefetch is already running downloads the same bytes twice.
    private var inFlight: [String: Task<URL, Error>] = [:]

    private static let temporaryPrefix = "tmp-"

    /// The real cache location. Computed without creating anything so it can be asserted
    /// against in a test without writing to the user's home directory. `namespace` isolates
    /// this from a host app's own Application Support contents — default it to your app's own
    /// name if you're not passing an explicit `directory` to `init`.
    public static func defaultDirectory(namespace: String = "RichTextEditor") throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        .appending(path: namespace, directoryHint: .isDirectory)
        .appending(path: "DocumentImages", directoryHint: .isDirectory)
    }

    public init(directory: URL? = nil, fetcher: ImageFetching) throws {
        self.directory = try directory ?? Self.defaultDirectory()
        self.fetcher = fetcher

        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        var mutable = self.directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }

    // MARK: - Reading

    /// The on-disk location of an image, fetching and persisting it if it is not cached.
    ///
    /// A cached file is returned without ever consulting the fetcher, which is what makes
    /// airplane-mode reads work: the network failing is not on the path at all.
    public func localURL(for key: String) async throws -> URL {
        if let cached = cachedURL(for: key) { return cached }
        if let existing = inFlight[key] { return try await existing.value }

        let task = Task<URL, Error> { [directory, fetcher] in
            let data = try await fetcher.data(for: key)
            let destination = Self.location(of: key, in: directory)
            let temporary = directory.appending(path: Self.temporaryPrefix + UUID().uuidString)
            try data.write(to: temporary, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            // replaceItemAt removes the temp file on success; clean up if it did not.
            try? FileManager.default.removeItem(at: temporary)
            return destination
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    /// The cached location, or `nil` if this key has never been fetched. Never touches the
    /// network — this is what a view can ask synchronously before deciding to show a
    /// placeholder.
    public func cachedURL(for key: String) -> URL? {
        let url = Self.location(of: key, in: directory)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    public func isCached(_ key: String) -> Bool {
        cachedURL(for: key) != nil
    }

    // MARK: - Prefetch and eviction

    /// Warms the cache for a set of keys, concurrently.
    ///
    /// Called in the same pass that pulls a document, per the PRD — a document synced without
    /// its images renders with holes in airplane mode, and the user has no way to fix that
    /// once they are offline. Best-effort by design: one image failing must not stop the rest.
    public func prefetch(keys: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for key in Set(keys) where !isCached(key) {
                group.addTask { [weak self] in
                    _ = try? await self?.localURL(for: key)
                }
            }
        }
    }

    /// Deletes cached images no longer referenced by any cached document.
    ///
    /// - Parameter liveKeys: the union of image keys across **all** cached documents. Passing
    ///   the keys of a single document would evict every other document's images.
    @discardableResult
    public func evictUnreferenced(keeping liveKeys: Set<String>) async -> Int {
        let live = Set(liveKeys.map(Self.filename))
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        var removed = 0
        for url in contents {
            let name = url.lastPathComponent
            // Skip in-flight downloads; they have no key association yet and deleting one
            // would turn a live fetch into a mysterious failure.
            guard !name.hasPrefix(Self.temporaryPrefix), !live.contains(name) else { continue }
            if (try? FileManager.default.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }

    // MARK: - Naming

    /// SHA-256 of the object key, hex-encoded. Object keys contain `/`, which cannot appear in
    /// a filename, and hashing sidesteps length limits and case-insensitive filesystems at the
    /// same time.
    static func filename(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func location(of key: String, in directory: URL) -> URL {
        directory.appending(path: filename(for: key))
    }
}
