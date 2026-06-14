import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Synced-mode favorites / dietary stores: optimistic toggle → repository upsert /
/// soft-delete, reload derives the active set (tombstones excluded), and the
/// one-shot UserDefaults→repository legacy migration. Local (UserDefaults) mode is
/// covered by `FavoritesStoreTests` / `DietaryPreferencesStoreTests` (unchanged).
@MainActor
struct FavoriteSyncStoreTests {
    private func isolated() -> UserDefaults { UserDefaults(suiteName: "test.favsync.\(UUID().uuidString)")! }

    private func makeFavorites(
        legacy: UserDefaults? = nil
    ) throws -> (FavoritesStore, FavoriteRecipeRepository) {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = FavoriteRecipeRepository(modelContainer: container)
        let session = SyncSession(selectedHouseholdId: "home", defaults: isolated())
        let writer = SyncWriter(
            outbox: SyncOutboxRepository(modelContainer: container),
            coordinator: nil,
            session: session
        )
        let store = FavoritesStore(repository: repo, session: session, syncWriter: writer, legacyDefaults: legacy ?? isolated())
        return (store, repo)
    }

    // MARK: Favorites

    @Test func toggleOnPersistsAndReloadDerivesSet() async throws {
        let (store, repo) = try makeFavorites()
        #expect(store.toggle("r1") == true)
        #expect(store.isFavorite("r1")) // optimistic, synchronous
        await store.drainPendingWrites()
        #expect(try await repo.loadAllFor("home").contains { $0.recipeID == "r1" && $0.deletedAt == nil })
        await store.reload()
        #expect(store.favoriteIDs == ["r1"])
    }

    @Test func toggleOffSoftDeletesTheSameRow() async throws {
        let (store, repo) = try makeFavorites()
        store.toggle("r1")
        await store.drainPendingWrites()
        store.toggle("r1") // un-favorite
        await store.drainPendingWrites()
        #expect(!store.isFavorite("r1"))
        let rows = try await repo.loadAllFor("home")
        #expect(rows.count == 1) // one row, not a second appended row
        #expect(rows.first?.deletedAt != nil) // tombstoned
    }

    @Test func reloadExcludesTombstones() async throws {
        let (store, repo) = try makeFavorites()
        try await repo.upsert("home", FavoriteRecipe.make(householdID: "home", recipeID: "active"))
        try await repo.upsert("home", FavoriteRecipe.make(
            householdID: "home", recipeID: "gone", deletedAt: Date(timeIntervalSince1970: 1)
        ))
        await store.reload()
        #expect(store.favoriteIDs == ["active"])
    }

    @Test func legacyFavoritesMigratedOnceThenBlobCleared() async throws {
        let legacy = isolated()
        legacy.set(#"["old1","old2"]"#, forKey: FavoritesStore.storageKey)
        let (store, repo) = try makeFavorites(legacy: legacy)
        await store.reload()
        #expect(store.favoriteIDs == ["old1", "old2"])
        #expect(try await repo.loadAllFor("home").map(\.recipeID).sorted() == ["old1", "old2"])
        #expect(legacy.string(forKey: FavoritesStore.storageKey) == nil) // migrated once → blob cleared
    }

    // MARK: Dietary

    @Test func dietaryAddRemoveSyncAndReload() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = DietaryPreferenceRepository(modelContainer: container)
        let session = SyncSession(selectedHouseholdId: "home", defaults: isolated())
        let writer = SyncWriter(outbox: SyncOutboxRepository(modelContainer: container), coordinator: nil, session: session)
        let store = DietaryPreferencesStore(repository: repo, session: session, syncWriter: writer, legacyDefaults: isolated())

        #expect(store.add("  Cilantro ") == "cilantro") // normalization preserved
        #expect(store.keywords == ["cilantro"])
        await store.drainPendingWrites()
        #expect(try await repo.loadAllFor("home").contains { $0.keyword == "cilantro" && $0.deletedAt == nil })

        store.remove("CILANTRO")
        await store.drainPendingWrites()
        #expect(store.keywords.isEmpty)
        let rows = try await repo.loadAllFor("home")
        #expect(rows.count == 1 && rows.first?.deletedAt != nil)

        await store.reload()
        #expect(store.keywords.isEmpty) // tombstone excluded
    }
}
