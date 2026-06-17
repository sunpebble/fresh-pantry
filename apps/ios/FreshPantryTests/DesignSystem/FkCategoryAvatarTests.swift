import Foundation
import Testing
import UIKit
@testable import FreshPantry

/// Guards `FkCategoryAvatar`'s synchronous first-frame memory hit. Like the recipe
/// covers, a category avatar whose thumbnail is already decoded in memory must
/// render on the FIRST frame instead of flashing the category glyph and then
/// swapping the photo in as the row scrolls into view (the "content keeps loading
/// as I scroll" feel). The avatar resolves the displayed image as
/// `image ?? memoryCachedImage(...)`, and `.task` uses the SAME maxPixel — so the
/// memory key must include maxPixel, or the synchronous hit silently misses.
@MainActor
struct FkCategoryAvatarTests {
    private var pngData: Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="
        )!
    }

    private func freshURLString() -> String {
        "https://example.com/avatar-\(UUID().uuidString).png"
    }

    @Test func emptyURLHasNoCachedImage() {
        #expect(FkCategoryAvatar.memoryCachedImage(imageUrl: "", maxPixel: 64) == nil)
    }

    @Test func uncachedURLHasNoCachedImage() {
        #expect(FkCategoryAvatar.memoryCachedImage(imageUrl: freshURLString(), maxPixel: 64) == nil)
    }

    /// Once a thumbnail is promoted into the memory tier, the synchronous lookup the
    /// view uses for its first frame returns it — no glyph→photo flash on scroll-in.
    @Test func promotedThumbnailResolvesSynchronously() {
        let urlString = freshURLString()
        let url = URL(string: urlString)!
        RemoteImageCache.persist(pngData, for: url)
        // Promote disk→memory for maxPixel 64 (what a completed `.task` does).
        _ = RemoteImageCache.cached(for: url, maxPixel: 64)
        #expect(FkCategoryAvatar.memoryCachedImage(imageUrl: urlString, maxPixel: 64) != nil)
    }

    /// The memory key is per-maxPixel: a thumbnail promoted at one render size is NOT
    /// a hit at another. This is exactly why the view must use ONE maxPixel for both
    /// the synchronous hit and the async `.task` — a mismatch would always miss.
    @Test func cachedImageIsKeyedByMaxPixel() {
        let urlString = freshURLString()
        let url = URL(string: urlString)!
        RemoteImageCache.persist(pngData, for: url)
        _ = RemoteImageCache.cached(for: url, maxPixel: 64)
        #expect(FkCategoryAvatar.memoryCachedImage(imageUrl: urlString, maxPixel: 64) != nil)
        #expect(FkCategoryAvatar.memoryCachedImage(imageUrl: urlString, maxPixel: 128) == nil)
    }
}
