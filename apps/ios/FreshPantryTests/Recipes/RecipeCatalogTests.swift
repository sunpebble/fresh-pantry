import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Tests for the DB-backed recipe catalog: the on-disk cache round-trip and the
/// `RecipesStore` source precedence (cache > bundle) + background DB refresh,
/// which together keep browse offline-first while sourcing from the database.
@MainActor
struct RecipeCatalogTests {
    private func recipe(id: String, name: String, category: String = "家常") -> Recipe {
        Recipe(
            id: id, name: name, category: category, difficulty: 2,
            cookingMinutes: 20, description: "", ingredients: [], steps: []
        )
    }

    /// Deterministic stub catalog (no live SDK) for the refresh path.
    private struct StubCatalog: RecipeCatalogFetching {
        let recipes: [Recipe]
        var isAvailable: Bool { true }
        func fetchAll() async -> [Recipe] { recipes }
    }

    private func tempCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-\(UUID().uuidString).json")
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.catalog.\(UUID().uuidString)")!
    }

    /// A bundle loader seeded with `recipes` via `LocalRecipeRepository`'s
    /// payload seam (encodes the array as the "bundled" JSON corpus).
    private func bundleRepo(_ recipes: [Recipe]) -> LocalRecipeRepository {
        let data = (try? JSONEncoder().encode(recipes)) ?? Data("[]".utf8)
        return LocalRecipeRepository(payload: data)
    }

    private func makeStore(
        bundled: [Recipe],
        cache: RecipeCatalogCache? = nil,
        remote: (any RecipeCatalogFetching)? = nil
    ) throws -> RecipesStore {
        let container = try ModelContainerFactory.makeInMemory()
        return RecipesStore(
            localRepository: bundleRepo(bundled),
            customRepository: CustomRecipeRepository(modelContainer: container),
            favoritesStore: FavoritesStore(defaults: isolatedDefaults()),
            householdID: "home",
            remoteCatalog: remote,
            catalogCache: cache,
            recipeOverlay: nil
        )
    }

    // MARK: Cache round-trip

    @Test func cacheRoundTrips() {
        let cache = RecipeCatalogCache(fileURL: tempCacheURL())
        #expect(cache.read() == nil) // 无文件 → nil
        cache.write([recipe(id: "a", name: "A"), recipe(id: "b", name: "B")])
        #expect(cache.read()?.map(\.id) == ["a", "b"])
    }

    @Test func emptyCacheReadsAsNil() {
        let cache = RecipeCatalogCache(fileURL: tempCacheURL())
        cache.write([])
        #expect(cache.read() == nil) // 空数组视为无缓存,回退 bundle
    }

    // MARK: Source precedence (cache > bundle)

    @Test func loadPrefersCacheOverBundle() async throws {
        let cache = RecipeCatalogCache(fileURL: tempCacheURL())
        cache.write([recipe(id: "db1", name: "DB菜")])
        let store = try makeStore(bundled: [recipe(id: "bundle1", name: "内置菜")], cache: cache)
        await store.load()
        #expect(store.recipes.map(\.id) == ["db1"]) // 用 DB 缓存,不用 bundle
    }

    @Test func loadFallsBackToBundleWhenNoCache() async throws {
        let store = try makeStore(
            bundled: [recipe(id: "bundle1", name: "内置菜")],
            cache: RecipeCatalogCache(fileURL: tempCacheURL()) // 空,无文件
        )
        await store.load()
        #expect(store.recipes.map(\.id) == ["bundle1"]) // 无缓存 → 内置兜底
    }

    // MARK: Background DB refresh

    @Test func refreshFromRemoteUpgradesAndWritesCache() async throws {
        let cache = RecipeCatalogCache(fileURL: tempCacheURL())
        let remote = StubCatalog(recipes: [
            recipe(id: "db1", name: "DB菜"), recipe(id: "db2", name: "DB菜2"),
        ])
        let store = try makeStore(
            bundled: [recipe(id: "bundle1", name: "内置菜")], cache: cache, remote: remote
        )
        // 直接驱动刷新(避免 load() 的后台 Task 竞态),验证升级为 DB 数据 + 落盘缓存
        await store.refreshCatalogFromRemote()
        #expect(store.recipes.map(\.id) == ["db1", "db2"])
        #expect(cache.read()?.map(\.id) == ["db1", "db2"])
    }

    @Test func emptyRemoteFetchKeepsBundleAndDoesNotCache() async throws {
        let cache = RecipeCatalogCache(fileURL: tempCacheURL())
        let store = try makeStore(
            bundled: [recipe(id: "bundle1", name: "内置菜")],
            cache: cache,
            remote: StubCatalog(recipes: []) // 离线/未播种 → 空
        )
        await store.load()
        await store.refreshCatalogFromRemote()
        #expect(store.recipes.map(\.id) == ["bundle1"]) // 空抓取不覆盖
        #expect(cache.read() == nil) // 不写空缓存
    }
}
