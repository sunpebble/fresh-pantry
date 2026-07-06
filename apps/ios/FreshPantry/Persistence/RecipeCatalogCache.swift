import Foundation

/// On-disk cache of the DB recipe catalog so the explore tab stays offline-first.
/// The last successful `RemoteRecipeCatalog` fetch is persisted to Application
/// Support and read on the next launch — before, and instead of when offline, a
/// network round-trip.
struct RecipeCatalogCache: Sendable {
    private let fileURL: URL

    /// Default location: `<ApplicationSupport>/recipe-catalog.json`. Returns nil
    /// when Application Support can't be resolved.
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
    /// (so the caller falls back to DB/local payload). Reuses the per-entry-resilient
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
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    /// The cached translated overlay for `lang`, or nil when absent/empty. This
    /// cache is populated only from the DB, so translations remain server-sourced
    /// while non-Chinese UI still works after the first successful fetch.
    func readOverlay(lang: String) -> [String: RecipeOverlayEntry]? {
        guard let data = try? Data(contentsOf: overlayURL(lang: lang)),
              let overlay = try? JSONDecoder().decode([String: RecipeOverlayEntry].self, from: data),
              !overlay.isEmpty else {
            return nil
        }
        return overlay
    }

    /// Persists a translated overlay atomically. Best-effort like `write(_:)`.
    func writeOverlay(_ overlay: [String: RecipeOverlayEntry], lang: String) {
        guard !overlay.isEmpty,
              let data = try? JSONEncoder().encode(overlay) else {
            return
        }
        let url = overlayURL(lang: lang)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private func overlayURL(lang: String) -> URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent("recipe-i18n-\(lang).json")
    }
}
