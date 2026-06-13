import CryptoKit
import SwiftUI
import UIKit

/// Persistent (memory + disk) cache for remote images — recipe covers (served from
/// Supabase Storage) and member avatars.
///
/// The point is the **synchronous** `cached(for:maxPixel:)`: a disk hit is decoded
/// and returned on the spot, so a cover/avatar already in the cache renders on the
/// FIRST frame after a cold launch instead of flashing a placeholder while the
/// network refetches. That cold-start flash is exactly the avatar bug `AsyncImage`
/// had — `AsyncImage` is always asynchronous, so its first frame is always the
/// placeholder. It also makes browse work offline once an image has been seen.
///
/// Disk bytes live in Caches (the OS may evict under storage pressure, which only
/// costs a refetch). Keyed by a SHA-256 of the absolute URL.
enum RemoteImageCache {
    /// Decoded, downsampled images keyed by `url#maxPixel` (so different render
    /// sizes don't collide). Memory tier; lost on restart, repopulated from disk.
    /// `nonisolated(unsafe)` is sound because `NSCache` is internally thread-safe.
    nonisolated(unsafe) private static let memory = NSCache<NSString, UIImage>()

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("RemoteImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func memoryKey(_ url: URL, _ maxPixel: Int) -> NSString {
        "\(url.absoluteString)#\(maxPixel)" as NSString
    }

    private static func diskURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }

    /// Synchronous **memory-tier** hit only — never touches disk, so it is safe to
    /// call from a SwiftUI view's `init`/`body` without blocking the main thread.
    /// A miss returns nil and the caller awaits `image(for:maxPixel:)`, which does
    /// the disk read + ImageIO decode off the synchronous render path. A full-res
    /// disk decode fanned across a `LazyVStack` of covers during one layout pass was
    /// the main-thread hang vector behind FRESH_PANTRY-13/14, so it must not run in
    /// view construction.
    nonisolated static func cachedInMemory(for url: URL, maxPixel: Int) -> UIImage? {
        memory.object(forKey: memoryKey(url, maxPixel))
    }

    /// Synchronous cache hit (memory, then disk). The disk branch is a full-res
    /// ImageIO decode and MUST NOT run on the main thread — call it only from the
    /// async `image(for:)` (or another background context), never from a view's
    /// `init`/`body`. Use `cachedInMemory(for:maxPixel:)` for the synchronous
    /// first-frame hit instead.
    nonisolated static func cached(for url: URL, maxPixel: Int) -> UIImage? {
        let key = memoryKey(url, maxPixel)
        if let hit = memory.object(forKey: key) { return hit }
        guard
            let data = try? Data(contentsOf: diskURL(for: url), options: .mappedIfSafe),
            let image = RecipeImageStore.downsample(data, maxPixel: maxPixel)
        else { return nil }
        memory.setObject(image, forKey: key)
        return image
    }

    /// Cached image, or download → persist bytes to disk → decode. Returns nil on
    /// failure (offline + not cached, non-2xx, undecodable) so the caller shows its
    /// placeholder. `@MainActor` so the decoded `UIImage` stays main-isolated for
    /// the SwiftUI `.task` that assigns it to `@State`.
    @MainActor static func image(for url: URL, maxPixel: Int) async -> UIImage? {
        if let hit = cached(for: url, maxPixel: maxPixel) { return hit }
        guard
            let (data, response) = try? await URLSession.shared.data(from: url),
            (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
        else { return nil }
        persist(data, for: url)
        guard let image = RecipeImageStore.downsample(data, maxPixel: maxPixel) else { return nil }
        memory.setObject(image, forKey: memoryKey(url, maxPixel))
        return image
    }

    /// Writes raw bytes to the on-disk tier. Used by `image(for:)`; exposed for tests
    /// to seed the cache and assert the synchronous cold-start hit.
    nonisolated static func persist(_ data: Data, for url: URL) {
        try? data.write(to: diskURL(for: url), options: .atomic)
    }
}

/// Remote image backed by `RemoteImageCache`: renders a cached hit on the first
/// frame (no placeholder flash on cold launch) and falls back to `placeholder`
/// while fetching or when offline-and-uncached. Drop-in replacement for the
/// `AsyncImage` recipe covers / avatars used before.
struct CachedRemoteImage<Placeholder: View>: View {
    private let url: URL?
    private let maxPixel: Int
    @ViewBuilder private let placeholder: () -> Placeholder
    @State private var image: UIImage?

    init(url: URL?, maxPixel: Int, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.maxPixel = maxPixel
        self.placeholder = placeholder
        // Synchronous MEMORY hit → first frame already has the image, with no disk
        // I/O on the main thread. A memory miss falls through to `.task(id: url)`
        // below, which reads + decodes from disk via `image(for:)` off the
        // synchronous render path (FRESH_PANTRY-13/14: no full-res decode in `init`).
        _image = State(initialValue: url.flatMap { RemoteImageCache.cachedInMemory(for: $0, maxPixel: maxPixel) })
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard image == nil, let url else { return }
            image = await RemoteImageCache.image(for: url, maxPixel: maxPixel)
        }
    }
}
