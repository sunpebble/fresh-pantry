import Foundation
import Supabase

/// Abstraction over the DB catalog fetch so `RecipesStore` can be unit-tested
/// with a stub (the concrete `RemoteRecipeCatalog` wraps the live SDK).
protocol RecipeCatalogFetching: Sendable {
    /// Whether a backend is configured (false → no remote, stay on cache/local).
    var isAvailable: Bool { get }
    /// The full catalog, or `[]` on any failure (caller falls back to cache/local).
    func fetchAll() async -> [Recipe]
    /// The translated overlay for `lang`, or nil on any failure / unsupported mode.
    func fetchOverlay(lang: String) async -> [String: RecipeOverlayEntry]?
}

extension RecipeCatalogFetching {
    func fetchOverlay(lang: String) async -> [String: RecipeOverlayEntry]? { nil }
}

/// DB-backed shared recipe catalog. Fetches the HowToCook corpus from the
/// Supabase `recipes` table (anon-readable, no household scope — the catalog is
/// the same for everyone) so the explore tab is sourced from the database.
/// `RecipeCatalogCache` keeps the last fetch on disk, so browse still works
/// offline after the first successful fetch (see `RecipesStore`).
///
/// Any failure (no backend configured, offline, decode error) degrades to an
/// empty result so the caller falls back to the cache or local test seam rather than
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
        "id,name,category,difficulty,cookingMinutes:cooking_minutes,description,ingredients,steps,tags,imageUrl:image_url,videoUrl:video_url,nutrition,stepDurations:step_durations"
    private static let overlayColumns = "recipe_id,name,category,description,ingredients,steps,tags"

    /// Fetches the full catalog. Returns `[]` on any failure so callers fall back
    /// to the on-disk cache or local payload.
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

    func fetchOverlay(lang: String) async -> [String: RecipeOverlayEntry]? {
        guard let client else { return nil }
        do {
            let rows: [RecipeI18nRow] = try await client
                .from("recipe_i18n")
                .select(Self.overlayColumns)
                .eq("lang", value: lang)
                .execute()
                .value
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.recipeId, $0.entry) })
        } catch {
            return nil
        }
    }
}

enum RecipeCatalogLoader {
    static func load(
        local: LocalRecipeRepository,
        remote: (any RecipeCatalogFetching)?,
        cache: RecipeCatalogCache?
    ) async -> [Recipe] {
        if let cache {
            let cached = await Task.detached(priority: .userInitiated) { cache.read() }.value
            if let cached, !cached.isEmpty { return cached }
        }
        if let remote, remote.isAvailable {
            let fresh = await remote.fetchAll()
            if !fresh.isEmpty {
                if let cache {
                    await Task.detached(priority: .utility) { cache.write(fresh) }.value
                }
                return fresh
            }
        }
        return await local.loadAll()
    }

    static func overlay(
        injected: [String: RecipeOverlayEntry]? = nil,
        remote: (any RecipeCatalogFetching)?,
        preferred: [String] = Bundle.main.preferredLocalizations
    ) async -> [String: RecipeOverlayEntry]? {
        if let injected { return injected }
        guard let lang = RecipeLocalizer.overlayLanguage(preferred: preferred),
              let remote, remote.isAvailable else { return nil }
        return await remote.fetchOverlay(lang: lang)
    }
}

private struct RecipeI18nRow: Decodable {
    let recipeId: String
    let name: String
    let category: String
    let description: String
    let ingredients: [RecipeOverlayEntry.IngredientOverlay]
    let steps: [String]
    let tags: [String]

    var entry: RecipeOverlayEntry {
        RecipeOverlayEntry(
            name: name,
            description: description,
            category: category,
            steps: steps,
            tags: tags,
            ingredients: ingredients
        )
    }

    private enum CodingKeys: String, CodingKey {
        case recipeId = "recipe_id"
        case name, category, description, ingredients, steps, tags
    }
}
