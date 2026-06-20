import Foundation

/// Drives the ingredient-detail nutrition card. CACHE-FIRST, then a best-effort
/// network lookup on a miss — mirrors the Flutter `foodDetailsProvider`
/// (`detailsFor` reads the cache, falls back to `client.lookup`, and persists
/// real results). The OFF lookup itself never throws (errors → nil + log), so a
/// flaky network surfaces as `.notFound`, never a crash.
@Observable
@MainActor
final class FoodDetailsStore {
    enum State: Equatable {
        case idle
        case loading
        case loaded(FoodDetails)
        case notFound
        case error
    }

    private(set) var state: State = .idle

    private let ingredient: Ingredient
    private let repository: FoodDetailsRepository
    private let client: OpenFoodFactsDetailsClient

    init(
        ingredient: Ingredient,
        repository: FoodDetailsRepository,
        client: OpenFoodFactsDetailsClient
    ) {
        self.ingredient = ingredient
        self.repository = repository
        self.client = client
    }

    /// Cache-first lookup: a fresh-version cache hit shows immediately; otherwise
    /// fetch from OFF, persist a real result, and show it. Idempotent — re-entry
    /// while already loaded/loading is a no-op.
    func load() async {
        switch state {
        case .loading, .loaded:
            return
        case .idle, .notFound, .error:
            break
        }

        state = .loading

        // 1) Cache (version-gated; a stale-schema row is treated as a miss).
        if let cached = try? await repository.cached(for: ingredient) {
            state = .loaded(cached)
            return
        }

        // 2) Network — best-effort. A nil result (not found / offline) → notFound.
        let fetched = try? await client.lookup(ingredient)
        guard let fetched else {
            state = .notFound
            return
        }

        try? await repository.store(fetched, for: ingredient)
        state = .loaded(fetched)
    }
}
