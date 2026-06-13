import ImageIO
import SwiftUI
import UIKit

/// Renders a recipe / dish cover from any of the three source shapes the data
/// uses, falling back to a caller-supplied placeholder when there is no usable
/// image. Mirrors Flutter's `RecipeImage` widget so every recipe surface resolves
/// covers identically:
///
/// - `assets/recipes/images/NAME.ext` → a BUNDLED image. The 174 HowToCook covers
///   ship inside the app (`RecipeImages/` folder reference), so browse works fully
///   offline — the upstream GitHub images are Git-LFS and the import tool notes the
///   LFS quota runs out, which is exactly why they are vendored locally, not linked.
/// - `file://...` → a locally-stored cover (a custom recipe's picked photo, saved by
///   `RecipeCoverStore`).
/// - `data:image/...;base64,...` → an inline image (AI-generated / pasted covers).
/// - `http(s)://...` → a remote image via `AsyncImage` (custom recipe / AI URLs).
///
/// Local sources are decoded once, downsampled, and memoized (`RecipeImageStore`),
/// so list scrolling and view rebuilds don't re-read or re-decode from disk.
struct RecipeImage<Fallback: View>: View {
    let source: String?
    /// Longest-edge pixel cap for the decoded REMOTE cover. Defaults to 900 (crisp
    /// for the full-width 220pt detail hero). Small surfaces pass their own render
    /// size so a 96pt card doesn't decode a 900px cover (≈10× the pixels it shows)
    /// on every cell — that per-cell full-res decode fanned across a scrolling list
    /// was the FRESH_PANTRY-13/14 main-thread hang vector.
    let maxPixel: Int
    @ViewBuilder var fallback: () -> Fallback

    init(source: String?, maxPixel: Int = 900, @ViewBuilder fallback: @escaping () -> Fallback) {
        self.source = source
        self.maxPixel = maxPixel
        self.fallback = fallback
    }

    var body: some View {
        let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            if let local = RecipeImageStore.localImage(for: trimmed) {
                Image(uiImage: local)
                    .resizable()
                    .scaledToFill()
            } else if let url = Self.remoteURL(trimmed) {
                // Covers now ship from Supabase Storage — disk-cache them so browse
                // works offline and cold launch shows the cover on the first frame.
                CachedRemoteImage(url: url, maxPixel: maxPixel) { fallback() }
            } else {
                // Non-empty but unresolvable (e.g. a missing bundled asset) — show the
                // placeholder rather than an empty box.
                fallback()
            }
        } else {
            fallback()
        }
    }

    /// Only `http(s)` strings are treated as remote; bundle/asset paths must never
    /// be coerced into a schemeless `URL` (that yields a broken relative request).
    private static func remoteURL(_ source: String) -> URL? {
        guard source.hasPrefix("http://") || source.hasPrefix("https://") else { return nil }
        return URL(string: source)
    }
}

/// Resolves + caches the non-remote recipe cover sources (bundled assets and inline
/// `data:` URIs) into downsampled `UIImage`s. `@MainActor`-isolated because it is
/// read straight from SwiftUI view bodies; the `NSCache` therefore needs no extra
/// synchronization to satisfy Swift 6 strict concurrency.
@MainActor
enum RecipeImageStore {
    /// The folder-reference subdirectory the HowToCook covers ship in.
    private static let subdirectory = "RecipeImages"
    /// Cap the decoded edge so a ~1600px source cover doesn't sit full-res in memory;
    /// 900px stays crisp for the largest use (the 220pt detail hero at 3×).
    private static let maxPixel = 900
    private static let cache = NSCache<NSString, UIImage>()

    /// Returns a decoded image for a bundled-asset or inline `data:` source, or nil
    /// for remote / empty / unresolvable sources (the caller then tries remote).
    static func localImage(for source: String) -> UIImage? {
        let key = source as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let data: Data?
        if source.lowercased().hasPrefix("data:image/") {
            data = inlineData(source)
        } else if source.hasPrefix("file://") {
            data = fileData(source)
        } else if source.hasPrefix("assets/") {
            data = bundleData(source)
        } else {
            return nil
        }

        guard let data, let image = downsample(data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Looks the bundled cover up by file name. Tries the folder-reference
    /// subdirectory first, then the bundle root (so a flat-bundled fallback works).
    private static func bundleData(_ source: String) -> Data? {
        let file = (source as NSString).lastPathComponent
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
        guard let url else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func fileData(_ source: String) -> Data? {
        guard let url = URL(string: source) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func inlineData(_ source: String) -> Data? {
        guard let range = source.range(of: ";base64,") else { return nil }
        return Data(base64Encoded: String(source[range.upperBound...]))
    }

    /// Decodes + downsamples via ImageIO (handles jpeg/png/webp). Falls back to a
    /// plain `UIImage(data:)` decode if the source can't produce a thumbnail.
    /// `nonisolated` + internal so the remote disk cache (`RemoteImageCache`) and
    /// `RemoteThumbnailStore` share this one ImageIO path off the main actor.
    nonisolated static func downsample(_ data: Data, maxPixel: Int = 900) -> UIImage? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: thumbnail)
    }
}
