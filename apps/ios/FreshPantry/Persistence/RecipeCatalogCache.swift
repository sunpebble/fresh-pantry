import Foundation

/// On-disk cache of the DB recipe catalog so the explore tab stays offline-first.
/// The last successful `RemoteRecipeCatalog` fetch is persisted to Application
/// Support and read on the next launch — before, and instead of when offline, a
/// network round-trip. The bundled `howtocook.json` is used only when no cache
/// exists yet (first launch with no network); see `RecipesStore`.
struct RecipeCatalogCache: Sendable {
    private let fileURL: URL

    /// Default location: `<ApplicationSupport>/recipe-catalog.json`. Returns nil
    /// when Application Support can't be resolved (keeps the store on bundle-only).
    init?(fileManager: FileManager = .default) {
        guard let dir = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        self.fileURL = dir.appendingPathComponent("recipe-catalog.json")
    }

    /// Test seam: cache at an explicit file URL.
    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The cached catalog, or nil when there is no readable, non-empty cache
    /// (so the caller falls back to the bundle). Reuses the per-entry-resilient
    /// decode so one bad row can't sink the cache.
    func read() -> [Recipe]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let recipes = LocalRecipeRepository.decode(data: data)
        return recipes.isEmpty ? nil : recipes
    }

    /// Persists the catalog atomically. Best-effort: a write failure is swallowed
    /// (the next fetch retries); the in-memory result is still used this run.
    func write(_ recipes: [Recipe]) {
        guard let data = try? JSONEncoder().encode(recipes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
