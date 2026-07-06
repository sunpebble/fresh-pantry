import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Tests for the DB-backed recipe catalog: on-disk cache round-trip, first-load
/// DB fetch, and local payload fallback for tests/previews.
@MainActor
struct RecipeCatalogTests {
    private func recipe(
        id: String,
        name: String,
        category: String = "家常",
        ingredients: [String] = []
    ) -> Recipe {
        Recipe(
            id: id, name: name, category: category, difficulty: 2,
            cookingMinutes: 20, description: "",
            ingredients: ingredients.map { RecipeIngredient(name: $0) },
            steps: []
        )
    }

    /// Deterministic stub catalog (no live SDK) for the refresh path.
    private struct StubCatalog: RecipeCatalogFetching {
        let recipes: [Recipe]
        var overlay: [String: RecipeOverlayEntry]? = nil
        var isAvailable: Bool { true }
        func fetchAll() async -> [Recipe] { recipes }
        func fetchOverlay(lang: String) async -> [String: RecipeOverlayEntry]? { overlay }
    }

    private func tempCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("recipe-catalog.json")
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.catalog.\(UUID().uuidString)")!
    }

    /// A local loader seeded with `recipes` via `LocalRecipeRepository`'s
    /// payload seam.
    private func bundleRepo(_ recipes: [Recipe]) -> LocalRecipeRepository {
        let data = (try? JSONEncoder().encode(recipes)) ?? Data("[]".utf8)
        return LocalRecipeRepository(payload: data)
    }

    private func makeStore(
        bundled: [Recipe],
        cache: RecipeCatalogCache? = nil,
        remote: (any RecipeCatalogFetching)? = nil,
        recipeOverlay: [String: RecipeOverlayEntry]? = nil
    ) throws -> RecipesStore {
        let container = try ModelContainerFactory.makeInMemory()
        return RecipesStore(
            localRepository: bundleRepo(bundled),
            customRepository: CustomRecipeRepository(modelContainer: container),
            favoritesStore: FavoritesStore(defaults: isolatedDefaults()),
            householdID: "home",
            remoteCatalog: remote,
            catalogCache: cache,
            recipeOverlay: recipeOverlay
        )
    }

    private func overlayEntry(
        name: String,
        category: String = "Home",
        ingredients: [String] = []
    ) -> RecipeOverlayEntry {
        RecipeOverlayEntry(
            name: name,
            description: "",
            category: category,
            steps: [],
            tags: [],
            ingredients: ingredients.map { .init(name: $0, unit: nil, note: nil) }
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

    @Test func overlayCacheRoundTrips() {
        let cache = RecipeCatalogCache(fileURL: tempCacheURL())
        #expect(cache.readOverlay(lang: "en") == nil)
        cache.writeOverlay(["r1": overlayEntry(name: "Translated")], lang: "en")
        #expect(cache.readOverlay(lang: "en")?["r1"]?.name == "Translated")
    }

    // MARK: Source precedence (cache > DB > local payload)

    @Test func loadPrefersCacheOverLocalPayload() async throws {
        let cache = RecipeCatalogCache(fileURL: tempCacheURL())
        cache.write([recipe(id: "db1", name: "DB菜")])
        let store = try makeStore(bundled: [recipe(id: "bundle1", name: "内置菜")], cache: cache)
        await store.load()
        #expect(store.recipes.map(\.id) == ["db1"]) // 用 DB 缓存,不用本地 payload
    }

    @Test func loadFetchesRemoteWhenNoCache() async throws {
        let cache = RecipeCatalogCache(fileURL: tempCacheURL())
        let store = try makeStore(
            bundled: [recipe(id: "local1", name: "本地菜")],
            cache: cache,
            remote: StubCatalog(recipes: [recipe(id: "remote1", name: "DB菜")])
        )
        await store.load()
        #expect(store.recipes.map(\.id) == ["remote1"])
        #expect(cache.read()?.map(\.id) == ["remote1"])
    }

    @Test func overlayFetchWritesCacheAndCacheBacksOfflineLoads() async {
        let cache = RecipeCatalogCache(fileURL: tempCacheURL())
        let entry = overlayEntry(name: "Cucumber Salad", ingredients: ["cucumber"])
        let remote = StubCatalog(recipes: [], overlay: ["r1": entry])
        let fresh = await RecipeCatalogLoader.overlay(remote: remote, cache: cache, preferred: ["en"])
        #expect(fresh?["r1"]?.name == "Cucumber Salad")

        let cached = await RecipeCatalogLoader.overlay(remote: nil, cache: cache, preferred: ["en"])
        #expect(cached?["r1"]?.name == "Cucumber Salad")
    }

    @Test func loadFallsBackToLocalPayloadWhenNoCacheOrRemote() async throws {
        let store = try makeStore(
            bundled: [recipe(id: "bundle1", name: "内置菜")],
            cache: RecipeCatalogCache(fileURL: tempCacheURL()) // 空,无文件
        )
        await store.load()
        #expect(store.recipes.map(\.id) == ["bundle1"]) // 测试/预览本地 payload 兜底
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

    @Test func emptyRemoteFetchKeepsLocalPayloadAndDoesNotCache() async throws {
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

    @Test func seasonalRecipesRankRawCatalogButReturnLocalizedDisplay() async throws {
        let store = try makeStore(
            bundled: [recipe(id: "summer", name: "拍黄瓜", ingredients: ["黄瓜"])],
            recipeOverlay: [
                "summer": overlayEntry(name: "Cucumber Salad", category: "Vegetarian", ingredients: ["cucumber"])
            ]
        )
        await store.load()
        let now = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 7, day: 1))!
        #expect(store.seasonalRecipes(now: now).map(\.name) == ["Cucumber Salad"])
    }
}
