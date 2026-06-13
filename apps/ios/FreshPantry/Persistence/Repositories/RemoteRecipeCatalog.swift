import Foundation
import Supabase

/// Abstraction over the DB catalog fetch so `RecipesStore` can be unit-tested
/// with a stub (the concrete `RemoteRecipeCatalog` wraps the live SDK).
protocol RecipeCatalogFetching: Sendable {
    /// Whether a backend is configured (false → no remote, stay on cache/bundle).
    var isAvailable: Bool { get }
    /// The full catalog, or `[]` on any failure (caller falls back to cache/bundle).
    func fetchAll() async -> [Recipe]
}

/// DB-backed shared recipe catalog. Fetches the HowToCook corpus from the
/// Supabase `recipes` table (anon-readable, no household scope — the catalog is
/// the same for everyone) so the explore tab is sourced from the database. The
/// bundled `howtocook.json` stays as the offline / first-launch seed and
/// `RecipeCatalogCache` keeps the last fetch on disk, so browse never breaks
/// offline (see `RecipesStore`).
///
/// Any failure (no backend configured, offline, decode error) degrades to an
/// empty result so the caller falls back to the cache or bundle rather than
/// surfacing an error or emptying the list.
struct RemoteRecipeCatalog: RecipeCatalogFetching {
    private let client: SupabaseClient?

    init(client: SupabaseClient?) {
        self.client = client
    }

    /// Whether a backend is configured at all (local-only mode → no remote).
    var isAvailable: Bool { client != nil }

    /// Columns aliased to the `Recipe` JSON keys (`cooking_minutes`→
    /// `cookingMinutes`, `image_url`→`imageUrl`) so each row decodes straight
    /// into `Recipe` via its lenient `Codable` — no separate row-shim type, and
    /// the numeric `ingredients` jsonb decodes through `RecipeIngredient`. Sync
    /// metadata columns are absent and default (remoteVersion 0, dates nil).
    private static let columns =
        "id,name,category,difficulty,cookingMinutes:cooking_minutes,description,ingredients,steps,tags,imageUrl:image_url,videoUrl:video_url"

    /// Fetches the full catalog. Returns `[]` on any failure so callers fall back
    /// to the on-disk cache or the bundled corpus.
    func fetchAll() async -> [Recipe] {
        guard let client else { return [] }
        do {
            let recipes: [Recipe] = try await client
                .from("recipes")
                .select(Self.columns)
                .execute()
                .value
            return recipes
        } catch {
            return []
        }
    }
}
