import Foundation
import Testing
@testable import FreshPantry

/// Guards the persistent remote-image cache that backs recipe covers (Supabase
/// Storage) and member avatars. The behaviour that matters is the SYNCHRONOUS
/// disk hit: once bytes are cached, `cached(for:maxPixel:)` returns the decoded
/// image on the spot, so a cover/avatar renders on the first frame after a cold
/// launch instead of flashing a placeholder — the avatar bug `AsyncImage` had.
@MainActor
struct RemoteImageCacheTests {
    /// A 1×1 PNG ImageIO can decode (stands in for a fetched avatar/cover body).
    private var pngData: Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="
        )!
    }

    /// Unique per test run so the simulator's persisted Caches dir can't leak state
    /// between runs.
    private func freshURL() -> URL {
        URL(string: "https://example.com/img-\(UUID().uuidString).png")!
    }

    @Test func uncachedURLReturnsNilSynchronously() {
        #expect(RemoteImageCache.cached(for: freshURL(), maxPixel: 64) == nil)
    }

    @Test func persistedBytesResolveSynchronously() {
        let url = freshURL()
        RemoteImageCache.persist(pngData, for: url) // what a successful fetch writes
        // Cold path: no in-memory entry yet, must come straight off disk.
        #expect(RemoteImageCache.cached(for: url, maxPixel: 64) != nil)
        // Warm path: second read is served from the in-memory tier.
        #expect(RemoteImageCache.cached(for: url, maxPixel: 64) != nil)
    }

    /// The synchronous first-frame path used in `CachedRemoteImage.init` must read
    /// memory ONLY — never disk — so view construction can't block the main thread
    /// (FRESH_PANTRY-13/14). A disk-only entry is invisible to `cachedInMemory`; the
    /// async `cached`/`image(for:)` path is what promotes it into memory.
    @Test func cachedInMemorySkipsDiskUntilPromoted() {
        let url = freshURL()
        RemoteImageCache.persist(pngData, for: url) // on disk, not yet in memory
        // Cold: memory-only lookup must NOT touch disk → miss.
        #expect(RemoteImageCache.cachedInMemory(for: url, maxPixel: 64) == nil)
        // The disk-reading path resolves it and promotes it into the memory tier.
        #expect(RemoteImageCache.cached(for: url, maxPixel: 64) != nil)
        // Now the memory-only lookup hits.
        #expect(RemoteImageCache.cachedInMemory(for: url, maxPixel: 64) != nil)
    }

    @Test func distinctURLsDoNotCollide() {
        let a = freshURL()
        let b = freshURL()
        RemoteImageCache.persist(pngData, for: a)
        #expect(RemoteImageCache.cached(for: a, maxPixel: 64) != nil)
        #expect(RemoteImageCache.cached(for: b, maxPixel: 64) == nil)
    }
}
