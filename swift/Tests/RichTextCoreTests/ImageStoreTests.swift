import Foundation
import Testing
@testable import RichTextCore

/// Build Order step 5. The cache is what makes P8 (offline correctness) possible, so the
/// tests here are mostly about what happens when the network is *not* available.
@Suite("ImageStore")
struct ImageStoreTests {

    /// Counts fetches and can be told to start failing, so "works offline" is testable
    /// without an actual network.
    private final class CountingFetcher: ImageFetching, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [String] = []
        private var _offline = false
        let payload: Data

        init(payload: Data = Data("image-bytes".utf8)) { self.payload = payload }

        var calls: [String] { lock.withLock { _calls } }
        func goOffline() { lock.withLock { _offline = true } }

        func data(for key: String) async throws -> Data {
            let offline = lock.withLock { _calls.append(key); return _offline }
            if offline { throw ImageStoreError.fetchFailed(key: key, statusCode: nil) }
            return payload
        }
    }

    private func makeStore(_ fetcher: ImageFetching) throws -> (ImageStore, URL) {
        let directory = URL(filePath: NSTemporaryDirectory())
            .appending(path: "ImageStoreTests-\(UUID().uuidString)")
        return (try ImageStore(directory: directory, fetcher: fetcher), directory)
    }

    // MARK: - The four correctness details

    /// Caches can be purged by the system at any time. If images lived there, a document that
    /// rendered yesterday would come back with holes today and nothing in the app could
    /// explain it — which is exactly the offline guarantee P8 is supposed to establish.
    @Test("The default cache lives in Application Support, never in Caches")
    func defaultDirectoryIsApplicationSupport() throws {
        let directory = try ImageStore.defaultDirectory()
        let path = directory.path(percentEncoded: false)
        #expect(path.contains("Application Support"))
        #expect(!path.contains("/Caches/"), "Caches can be purged by the system.")
        // Compared as components rather than a suffix: the URL carries a directory hint, so
        // its path string ends with a separator.
        #expect(directory.pathComponents.suffix(2) == ["RichTextEditor", "DocumentImages"])
    }

    @Test("Keys containing slashes are safe as filenames")
    func keysWithSlashesAreHashed() throws {
        let name = ImageStore.filename(for: "doc-images/2026/09/a.jpg")
        #expect(!name.contains("/"))
        #expect(name.count == 64, "Expected a hex SHA-256.")
        let isHex = name.allSatisfy(\.isHexDigit)
        #expect(isHex)
        // Distinct keys must not collide, including ones differing only in separator.
        #expect(name != ImageStore.filename(for: "doc-images_2026_09_a.jpg"))
    }

    @Test("The cache directory is excluded from backup")
    func directoryIsExcludedFromBackup() throws {
        let (store, directory) = try makeStore(CountingFetcher())
        _ = store
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true, "Cached images must not bloat iCloud backups.")
    }

    @Test("A fetched image is written to disk and served from there afterwards")
    func fetchThenCache() async throws {
        let fetcher = CountingFetcher()
        let (store, _) = try makeStore(fetcher)

        let first = try await store.localURL(for: "doc-images/a.jpg")
        #expect(FileManager.default.fileExists(atPath: first.path(percentEncoded: false)))
        #expect(try Data(contentsOf: first) == fetcher.payload)

        let second = try await store.localURL(for: "doc-images/a.jpg")
        #expect(first == second)
        #expect(fetcher.calls == ["doc-images/a.jpg"], "A cached image must not be refetched.")
    }

    // MARK: - Offline behaviour, which is the whole point

    /// The P8 guarantee, stated directly: once an image is cached, the network is not on the
    /// read path at all, so it failing changes nothing.
    @Test("A cached image is served with the fetcher failing every request")
    func cachedImagesSurviveGoingOffline() async throws {
        let fetcher = CountingFetcher()
        let (store, _) = try makeStore(fetcher)
        let key = "doc-images/cached.jpg"
        _ = try await store.localURL(for: key)

        fetcher.goOffline()

        let url = try await store.localURL(for: key)
        #expect(try Data(contentsOf: url) == fetcher.payload)
        #expect(fetcher.calls.count == 1, "Offline reads must not even consult the fetcher.")
    }

    @Test("An uncached image while offline fails rather than returning an empty file")
    func uncachedImageOfflineFails() async throws {
        let fetcher = CountingFetcher()
        fetcher.goOffline()
        let (store, directory) = try makeStore(fetcher)

        await #expect(throws: ImageStoreError.self) {
            try await store.localURL(for: "doc-images/never-seen.jpg")
        }
        // A failed fetch must leave nothing behind that a later call would mistake for a hit.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(leftovers.isEmpty, "A failed fetch left files behind: \(leftovers)")
        #expect(await store.isCached("doc-images/never-seen.jpg") == false)
    }

    @Test("cachedURL never touches the network")
    func cachedURLIsPurelyLocal() async throws {
        let fetcher = CountingFetcher()
        let (store, _) = try makeStore(fetcher)
        #expect(await store.cachedURL(for: "doc-images/a.jpg") == nil)
        #expect(fetcher.calls.isEmpty)
    }

    // MARK: - Prefetch and eviction

    @Test("Prefetch warms every key it is given")
    func prefetchWarmsTheCache() async throws {
        let fetcher = CountingFetcher()
        let (store, _) = try makeStore(fetcher)
        let keys = ["doc-images/a.jpg", "doc-images/b.jpg", "doc-images/c.jpg"]

        await store.prefetch(keys: keys)
        for key in keys {
            #expect(await store.isCached(key), "\(key) was not prefetched.")
        }
        #expect(Set(fetcher.calls) == Set(keys))
    }

    /// Prefetch is driven straight off the document being synced, which is the only way a
    /// cached document renders completely in airplane mode.
    @Test("Prefetch takes its keys straight from a Delta")
    func prefetchFromADelta() async throws {
        let fetcher = CountingFetcher()
        let (store, _) = try makeStore(fetcher)
        let delta = try FixtureCorpus.named("adjacent-images").delta

        await store.prefetch(keys: delta.imageKeys)
        #expect(await store.isCached("doc-images/first.jpg"))
        #expect(await store.isCached("doc-images/second.jpg"))
    }

    @Test("One image failing does not stop the rest of a prefetch")
    func prefetchIsBestEffort() async throws {
        struct FlakyFetcher: ImageFetching {
            func data(for key: String) async throws -> Data {
                if key.contains("bad") { throw ImageStoreError.fetchFailed(key: key, statusCode: 500) }
                return Data("ok".utf8)
            }
        }
        let (store, _) = try makeStore(FlakyFetcher())
        await store.prefetch(keys: ["doc-images/good.jpg", "doc-images/bad.jpg", "doc-images/also-good.jpg"])

        #expect(await store.isCached("doc-images/good.jpg"))
        #expect(await store.isCached("doc-images/also-good.jpg"))
        #expect(await store.isCached("doc-images/bad.jpg") == false)
    }

    @Test("Eviction removes exactly the unreferenced images")
    func evictionKeepsLiveKeys() async throws {
        let (store, _) = try makeStore(CountingFetcher())
        await store.prefetch(keys: ["doc-images/keep.jpg", "doc-images/drop.jpg", "doc-images/also-drop.jpg"])

        let removed = await store.evictUnreferenced(keeping: ["doc-images/keep.jpg"])
        #expect(removed == 2)
        #expect(await store.isCached("doc-images/keep.jpg"))
        #expect(await store.isCached("doc-images/drop.jpg") == false)
        #expect(await store.isCached("doc-images/also-drop.jpg") == false)
    }

    /// The live set is the union across *all* cached documents. Passing one document's keys
    /// would evict every other document's images and quietly break their offline reads.
    @Test("Eviction is driven by the union of keys across every cached document")
    func evictionUsesTheUnionAcrossDocuments() async throws {
        let (store, _) = try makeStore(CountingFetcher())
        let documents = [
            try FixtureCorpus.named("adjacent-images").delta,
            try FixtureCorpus.named("image-with-alt").delta,
        ]
        for document in documents { await store.prefetch(keys: document.imageKeys) }
        await store.prefetch(keys: ["doc-images/orphan.jpg"])

        let live = Set(documents.flatMap(\.imageKeys))
        await store.evictUnreferenced(keeping: live)

        for key in live {
            #expect(await store.isCached(key), "\(key) was evicted despite being live.")
        }
        #expect(await store.isCached("doc-images/orphan.jpg") == false)
    }

    // MARK: - Concurrency

    /// A view appearing mid-prefetch must not start a second download of the same bytes.
    @Test("Concurrent requests for one key result in a single fetch")
    func concurrentRequestsCoalesce() async throws {
        struct SlowFetcher: ImageFetching {
            let counter: Counter
            func data(for key: String) async throws -> Data {
                await counter.increment()
                try await Task.sleep(for: .milliseconds(50))
                return Data("slow".utf8)
            }
        }
        actor Counter {
            private(set) var value = 0
            func increment() { value += 1 }
        }

        let counter = Counter()
        let (store, _) = try makeStore(SlowFetcher(counter: counter))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { _ = try? await store.localURL(for: "doc-images/contended.jpg") }
            }
        }
        #expect(await counter.value == 1, "The same image was downloaded more than once.")
    }
}
