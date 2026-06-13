import Foundation

/// Read-only cross-domain search store for the global search overlay — a thin
/// snapshot of the inventory + shopping scopes filtered by a single query, ported
/// from the Flutter `filteredInventoryProvider` / `filteredShoppingProvider`.
///
/// Loads ONCE on present (`load()`); a transient overlay doesn't need to track
/// live mutations, and it is NOT a second source of truth (no persistence / sync).
/// Matching is case-insensitive contains on the name OR category, mirroring
/// search_provider.dart. Recipes (bundled + custom) are included; the 食材百科
/// section remains deferred — it lives inside ingredient detail.
@Observable
@MainActor
final class GlobalSearchStore {
    private let inventoryRepository: InventoryRepository
    private let shoppingRepository: ShoppingRepository
    private let localRecipeRepository: LocalRecipeRepository
    private let customRecipeRepository: CustomRecipeRepository
    private let householdID: String

    var query: String = ""
    private(set) var inventory: [Ingredient] = []
    private(set) var shopping: [ShoppingItem] = []
    private(set) var recipes: [Recipe] = []
    private(set) var hasLoaded = false

    init(
        inventoryRepository: InventoryRepository,
        shoppingRepository: ShoppingRepository,
        localRecipeRepository: LocalRecipeRepository,
        customRecipeRepository: CustomRecipeRepository,
        householdID: String
    ) {
        self.inventoryRepository = inventoryRepository
        self.shoppingRepository = shoppingRepository
        self.localRecipeRepository = localRecipeRepository
        self.customRecipeRepository = customRecipeRepository
        self.householdID = householdID
    }

    /// Snapshots inventory, shopping, and the merged recipe corpus. Best-effort:
    /// a load failure surfaces an empty scope rather than blocking the overlay.
    func load() async {
        async let inventoryLoad = (try? await inventoryRepository.loadAllFor(householdID)) ?? []
        async let shoppingLoad = (try? await shoppingRepository.loadAllFor(householdID)) ?? []
        async let bundledLoad = await localRecipeRepository.loadAll()
        async let customLoad = (try? await customRecipeRepository.loadAllFor(householdID)) ?? []
        inventory = await inventoryLoad
        shopping = await shoppingLoad
        let bundled = await bundledLoad
        let custom = await customLoad
        recipes = RecipesStore.merge(bundled: bundled, custom: custom)
        hasLoaded = true
    }

    var trimmedQuery: String { query.trimmed }
    var isSearching: Bool { !trimmedQuery.isEmpty }

    /// Inventory rows whose name OR category matches the query (pinyin-aware).
    var filteredInventory: [Ingredient] {
        let needle = trimmedQuery.lowercased()
        guard !needle.isEmpty else { return [] }
        return inventory.filter {
            PinyinMatcher.matches($0.name, query: needle)
                || PinyinMatcher.matches($0.category ?? "", query: needle)
        }
    }

    /// Shopping rows whose name OR category matches the query (pinyin-aware).
    var filteredShopping: [ShoppingItem] {
        let needle = trimmedQuery.lowercased()
        guard !needle.isEmpty else { return [] }
        return shopping.filter {
            PinyinMatcher.matches($0.name, query: needle)
                || PinyinMatcher.matches($0.category, query: needle)
        }
    }

    /// Recipe rows whose name OR any ingredient matches the query (pinyin-aware).
    var filteredRecipes: [Recipe] {
        let needle = trimmedQuery.lowercased()
        guard !needle.isEmpty else { return [] }
        return recipes.filter { recipe in
            if PinyinMatcher.matches(recipe.name, query: needle) { return true }
            return recipe.ingredients.contains {
                PinyinMatcher.matches($0.name, query: needle)
            }
        }
    }

    var hasResults: Bool {
        !filteredInventory.isEmpty || !filteredShopping.isEmpty || !filteredRecipes.isEmpty
    }
}
