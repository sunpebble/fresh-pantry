import SwiftUI

/// Global search overlay (presented from the 首页 toolbar) — a single entry point
/// to find any 库存 or 购物清单 item from anywhere, with recent-search history.
/// Ports the Flutter `SearchOverlay` (Phase 1: 库存 + 购物 + 历史; the online
/// 食材百科 section is deferred — it already lives inside ingredient detail).
///
/// Routing: an inventory hit pushes its detail INSIDE this overlay's own stack
/// (self-contained — builds its own `InventoryStore`); a shopping hit dismisses
/// and switches to the 购物 tab (the shopping list has no per-item detail screen).
struct GlobalSearchView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    /// Switches the root selection to the 购物 tab and highlights `itemID`.
    var onSelectShopping: (String) -> Void = { _ in }

    @State private var store: GlobalSearchStore?
    @State private var recipesStore: RecipesStore?
    @State private var customStore: CustomRecipeStore?
    @State private var selectedRecipe: Recipe?
    /// Built lazily so an inventory hit can push a fully-functional detail screen
    /// (IngredientDetailView requires an InventoryStore for its edit/删除/加购).
    @State private var inventoryStore: InventoryStore?
    /// UserDefaults-backed; a fresh instance reads the persisted recents.
    @State private var history = SearchHistoryStore()
    @State private var selectedIngredient: Ingredient?

    var body: some View {
        NavigationStack {
            Group {
                if let store {
                    content(store)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.fkSurface)
                }
            }
            .navigationTitle(String(localized: "search.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "search.done")) { dismiss() }
                }
            }
            .navigationDestination(item: $selectedIngredient) { ingredient in
                if let inventoryStore {
                    IngredientDetailView(ingredient: ingredient, store: inventoryStore)
                }
            }
            .navigationDestination(item: $selectedRecipe) { recipe in
                if let recipesStore, let customStore {
                    RecipeDetailView(
                        recipe: recipe,
                        store: recipesStore,
                        customStore: customStore,
                        isCustom: customStore.recipes.contains { $0.id == recipe.id }
                    )
                }
            }
        }
        .tint(.fkPrimary)
        .task {
            if store == nil {
                let search = GlobalSearchStore(
                    inventoryRepository: dependencies.inventoryRepository,
                    shoppingRepository: dependencies.shoppingRepository,
                    localRecipeRepository: dependencies.localRecipeRepository,
                    customRecipeRepository: dependencies.customRecipeRepository,
                    householdID: dependencies.householdID,
                    remoteCatalog: dependencies.remoteRecipeCatalog,
                    catalogCache: dependencies.recipeCatalogCache
                )
                await search.load()
                store = search
            }
            if recipesStore == nil {
                let built = RecipesStore(
                    localRepository: dependencies.localRecipeRepository,
                    customRepository: dependencies.customRecipeRepository,
                    favoritesStore: dependencies.favoritesStore,
                    householdID: dependencies.householdID,
                    inventoryRepository: dependencies.inventoryRepository,
                    dietaryStore: dependencies.dietaryPreferencesStore,
                    dietPreferenceStore: dependencies.dietPreferenceStore,
                    remoteCatalog: dependencies.remoteRecipeCatalog,
                    catalogCache: dependencies.recipeCatalogCache
                )
                await built.load()
                recipesStore = built
            }
            if customStore == nil {
                let built = CustomRecipeStore(
                    repository: dependencies.customRecipeRepository,
                    householdID: dependencies.householdID,
                    syncWriter: dependencies.syncWriter
                )
                await built.load()
                customStore = built
            }
            if inventoryStore == nil {
                let inv = InventoryStore(
                    repository: dependencies.inventoryRepository,
                    foodLogRepository: dependencies.foodLogRepository,
                    householdID: dependencies.householdID,
                    syncWriter: dependencies.syncWriter
                )
                await inv.load()
                inventoryStore = inv
            }
        }
    }

    @ViewBuilder
    private func content(_ store: GlobalSearchStore) -> some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            FkSearchField(text: $store.query, placeholder: String(localized: "search.placeholder"))
                .padding(.horizontal, FkSpacing.lg)
                .padding(.vertical, FkSpacing.sm)

            if store.isSearching {
                if store.hasResults {
                    resultsList(store)
                } else {
                    FkEmptyState(
                        systemImage: "magnifyingglass",
                        title: String(localized: "search.noResults \(store.trimmedQuery)"),
                        message: String(localized: "recipe.list.tryAnotherKeyword")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                historyPanel(store)
            }
        }
        .background(Color.fkSurface)
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: Results

    private func resultsList(_ store: GlobalSearchStore) -> some View {
        List {
            if !store.filteredInventory.isEmpty {
                Section {
                    ForEach(store.filteredInventory, id: \.fkListIdentityKey) { item in
                        Button {
                            history.record(store.trimmedQuery)
                            selectedIngredient = item
                        } label: {
                            IngredientRow(ingredient: item)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.fkSurfaceContainerLowest)
                    }
                } header: {
                    Text(String(localized: "search.inventoryCount \(store.filteredInventory.count)"))
                }
            }
            if !store.filteredShopping.isEmpty {
                Section {
                    ForEach(store.filteredShopping, id: \.id) { item in
                        Button {
                            history.record(store.trimmedQuery)
                            dismiss()
                            onSelectShopping(item.id)
                        } label: {
                            shoppingRow(item)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.fkSurfaceContainerLowest)
                    }
                } header: {
                    Text(String(localized: "search.shoppingCount \(store.filteredShopping.count)"))
                }
            }
            if !store.filteredRecipes.isEmpty {
                Section {
                    ForEach(store.filteredRecipes, id: \.id) { recipe in
                        Button {
                            history.record(store.trimmedQuery)
                            selectedRecipe = recipe
                        } label: {
                            recipeRow(recipe)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.fkSurfaceContainerLowest)
                    }
                } header: {
                    Text(String(localized: "search.recipesCount \(store.filteredRecipes.count)"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.fkSurface)
    }

    private func recipeRow(_ recipe: Recipe) -> some View {
        HStack(spacing: FkSpacing.md) {
            FkCategoryAvatar(imageUrl: recipe.imageUrl ?? "", category: recipe.category, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name)
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurface)
                Text(recipe.category)
                    .font(.fkLabelSmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            Spacer(minLength: 0)
            Image(systemName: "book")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.fkOnSurfaceVariant)
        }
    }

    private func shoppingRow(_ item: ShoppingItem) -> some View {
        HStack(spacing: FkSpacing.md) {
            FkCategoryAvatar(imageUrl: "", category: item.category, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurface)
                if !item.category.trimmed.isEmpty {
                    Text(FoodCategories.displayLabel(for: item.category))
                        .font(.fkLabelSmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
            Spacer(minLength: 0)
            if item.isChecked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.fkSuccess)
            }
            Image(systemName: "cart")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.fkOnSurfaceVariant)
        }
    }

    // MARK: History

    @ViewBuilder
    private func historyPanel(_ store: GlobalSearchStore) -> some View {
        if history.entries.isEmpty {
            FkEmptyState(
                systemImage: "magnifyingglass",
                title: String(localized: "search.emptyTitle"),
                message: String(localized: "search.emptyMessage")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(history.entries, id: \.self) { entry in
                        Button {
                            store.query = entry
                        } label: {
                            HStack(spacing: FkSpacing.md) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.fkOnSurfaceVariant)
                                Text(entry)
                                    .font(.fkBodyMedium)
                                    .foregroundStyle(Color.fkOnSurface)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.fkSurfaceContainerLowest)
                        .swipeActions {
                            Button(role: .destructive) { history.remove(entry) } label: {
                                Label(String(localized: "search.delete"), systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(String(localized: "search.recentSearches"))
                        Spacer()
                        Button(String(localized: "search.clear")) { history.clear() }
                            .font(.fkLabelSmall)
                            .foregroundStyle(Color.fkPrimary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.fkSurface)
        }
    }
}
