import SwiftUI
import UIKit

/// Category-tinted avatar: a rounded tint box showing the food image when one is
/// available, else the category glyph in the palette ink. Ported from the
/// Flutter avatar box used by `IngredientCard` / the detail hero.
///
/// Remote images (OFF product shots) are downsampled to the rendered size via
/// `RemoteThumbnailStore` rather than `AsyncImage` — list rows would otherwise
/// decode every source at full resolution, the exact memory blow-up the Flutter
/// list covers hit before capping decode to the render box.
struct FkCategoryAvatar: View {
    let imageUrl: String
    let category: String?
    var size: CGFloat = 48
    var cornerRadius: CGFloat = FkRadius.md
    var iconScale: CGFloat = 0.62

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        let palette = FkCategoryIcon.palette(for: category)
        // One render-size pixel cap, shared by the synchronous memory hit below and
        // the async `.task` — they MUST match or the memory key won't hit.
        let maxPixel = Int(size * max(displayScale, 1))
        // Synchronous MEMORY hit so an already-decoded thumbnail renders on the FIRST
        // frame (no glyph→photo flash as the row scrolls in). Memory-tier only, so
        // it's safe on the render path; a miss falls through to `.task` (disk/network)
        // exactly as `CachedRemoteImage` does for recipe covers / avatars.
        let displayed = image ?? Self.memoryCachedImage(imageUrl: imageUrl, maxPixel: maxPixel)
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(palette.tint)
            .frame(width: size, height: size)
            .overlay {
                if let displayed {
                    Image(uiImage: displayed)
                        .resizable()
                        .scaledToFill()
                } else {
                    glyph(palette)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: imageUrl) {
                guard let url = URL(string: imageUrl), !imageUrl.isEmpty else {
                    image = nil
                    return
                }
                image = await RemoteThumbnailStore.thumbnail(for: url, maxPixel: maxPixel)
            }
    }

    /// Synchronous memory-tier hit for the already-decoded thumbnail, or nil for an
    /// empty/invalid URL or a miss. Reads memory only (never disk), so it is safe to
    /// call straight from `body` for the first-frame render (mirrors
    /// `RemoteImageCache.cachedInMemory`, the path that kills the cold-start flash).
    static func memoryCachedImage(imageUrl: String, maxPixel: Int) -> UIImage? {
        guard !imageUrl.isEmpty, let url = URL(string: imageUrl) else { return nil }
        return RemoteImageCache.cachedInMemory(for: url, maxPixel: maxPixel)
    }

    private func glyph(_ palette: FkCategoryColors) -> some View {
        Image(systemName: FkCategoryIcon.symbol(for: category))
            .font(.system(size: size * iconScale, weight: .semibold))
            .foregroundStyle(palette.ink)
    }
}

/// Fetch-and-downsample cache for remote OFF food thumbnails. Delegates to
/// `RemoteImageCache` so the bytes persist to disk (offline-capable, survives
/// restarts) instead of relying on `URLSession`'s volatile URLCache.
@MainActor
enum RemoteThumbnailStore {
    static func thumbnail(for url: URL, maxPixel: Int) async -> UIImage? {
        await RemoteImageCache.image(for: url, maxPixel: maxPixel)
    }
}
