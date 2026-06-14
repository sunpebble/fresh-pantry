import Foundation

/// Pure local⇄remote reconciliation rule: remote rows are authoritative, and
/// only still-unsynced local rows survive alongside them.
///
/// Ported from the `_mergeRemoteXWithLocalOnly` + `_isLocalOnlyX` helpers in
/// `lib/sync/household_content_sync_coordinator.dart`. Kept SDK-free and pure so
/// the merge contract is unit-testable without SwiftData / Supabase.
///
/// For each entity the result is: every remote row, followed by the local rows
/// that are LOCAL-ONLY (never synced), NOT already present remotely by id, and
/// ALLOWED by the upload scope (no pending op claims them for another
/// household — parity invariant #7). Remote wins on id collisions, a synced
/// local row is dropped (remote is the source of truth), and a soft-deleted
/// local row is dropped (its remote absence already reflects the delete).
enum HouseholdMergePolicy {
    static func mergeInventory(
        remote: [Ingredient],
        local: [Ingredient],
        scope: LocalUploadScope
    ) -> [Ingredient] {
        merge(
            remote: remote,
            local: local,
            scope: scope,
            entityType: .inventoryItem,
            id: { $0.id },
            isLocalOnly: isLocalOnlyInventory
        )
    }

    static func mergeShopping(
        remote: [ShoppingItem],
        local: [ShoppingItem],
        scope: LocalUploadScope
    ) -> [ShoppingItem] {
        merge(
            remote: remote,
            local: local,
            scope: scope,
            entityType: .shoppingItem,
            id: { $0.id },
            isLocalOnly: isLocalOnlyShopping
        )
    }

    static func mergeCustomRecipe(
        remote: [Recipe],
        local: [Recipe],
        scope: LocalUploadScope
    ) -> [Recipe] {
        merge(
            remote: remote,
            local: local,
            scope: scope,
            entityType: .customRecipe,
            id: { $0.id },
            isLocalOnly: isLocalOnlyRecipe
        )
    }

    static func mergeMealPlan(
        remote: [MealPlanEntry],
        local: [MealPlanEntry],
        scope: LocalUploadScope
    ) -> [MealPlanEntry] {
        merge(
            remote: remote,
            local: local,
            scope: scope,
            entityType: .mealPlanEntry,
            id: { $0.id },
            isLocalOnly: isLocalOnlyMealPlan
        )
    }

    static func mergeFoodLog(
        remote: [FoodLogEntry],
        local: [FoodLogEntry],
        scope: LocalUploadScope
    ) -> [FoodLogEntry] {
        merge(
            remote: remote,
            local: local,
            scope: scope,
            entityType: .foodLogEntry,
            id: { $0.id },
            isLocalOnly: isLocalOnlyFoodLog
        )
    }

    static func mergeFavoriteRecipe(
        remote: [FavoriteRecipe],
        local: [FavoriteRecipe],
        scope: LocalUploadScope
    ) -> [FavoriteRecipe] {
        merge(
            remote: remote,
            local: local,
            scope: scope,
            entityType: .favoriteRecipe,
            id: { $0.id },
            isLocalOnly: isLocalOnlyFavoriteRecipe
        )
    }

    static func mergeDietaryPreference(
        remote: [DietaryPreference],
        local: [DietaryPreference],
        scope: LocalUploadScope
    ) -> [DietaryPreference] {
        merge(
            remote: remote,
            local: local,
            scope: scope,
            entityType: .dietaryPreference,
            id: { $0.id },
            isLocalOnly: isLocalOnlyDietaryPreference
        )
    }

    // MARK: Incremental patch (delta pull)

    static func patchInventory(remoteDelta: [Ingredient], local: [Ingredient]) -> [Ingredient] {
        patch(remoteDelta: remoteDelta, local: local, id: \.id)
    }

    static func patchShopping(remoteDelta: [ShoppingItem], local: [ShoppingItem]) -> [ShoppingItem] {
        patch(remoteDelta: remoteDelta, local: local, id: \.id)
    }

    static func patchCustomRecipe(remoteDelta: [Recipe], local: [Recipe]) -> [Recipe] {
        patch(remoteDelta: remoteDelta, local: local, id: \.id)
    }

    static func patchMealPlan(remoteDelta: [MealPlanEntry], local: [MealPlanEntry]) -> [MealPlanEntry] {
        patch(remoteDelta: remoteDelta, local: local, id: \.id)
    }

    static func patchFoodLog(remoteDelta: [FoodLogEntry], local: [FoodLogEntry]) -> [FoodLogEntry] {
        patch(remoteDelta: remoteDelta, local: local, id: \.id)
    }

    static func patchFavoriteRecipe(remoteDelta: [FavoriteRecipe], local: [FavoriteRecipe]) -> [FavoriteRecipe] {
        patch(remoteDelta: remoteDelta, local: local, id: \.id)
    }

    static func patchDietaryPreference(remoteDelta: [DietaryPreference], local: [DietaryPreference]) -> [DietaryPreference] {
        patch(remoteDelta: remoteDelta, local: local, id: \.id)
    }

    /// Applies an incremental remote delta onto the local snapshot: tombstones
    /// drop synced rows, upserts replace by id, unseen locals are kept.
    private static func patch<Element>(
        remoteDelta: [Element],
        local: [Element],
        id: KeyPath<Element, String>
    ) -> [Element] {
        var deltaById: [String: Element] = [:]
        var deletedIds = Set<String>()
        for delta in remoteDelta {
            let itemId = delta[keyPath: id]
            if isSoftDeleted(delta) {
                deltaById.removeValue(forKey: itemId)
                deletedIds.insert(itemId)
            } else {
                deltaById[itemId] = delta
                deletedIds.remove(itemId)
            }
        }
        var merged: [Element] = []
        var seen = Set<String>()
        for item in local {
            let itemId = item[keyPath: id]
            if deletedIds.contains(itemId) { continue }
            if let delta = deltaById[itemId], !isSoftDeleted(delta) {
                merged.append(delta)
            } else if deltaById[itemId] == nil {
                merged.append(item)
            }
            seen.insert(itemId)
        }
        for (itemId, delta) in deltaById where !seen.contains(itemId) {
            merged.append(delta)
        }
        return merged
    }

    private static func isSoftDeleted<T>(_ row: T) -> Bool {
        switch row {
        case let item as Ingredient: return item.deletedAt != nil
        case let item as ShoppingItem: return item.deletedAt != nil
        case let item as Recipe: return item.deletedAt != nil
        case let item as MealPlanEntry: return item.deletedAt != nil
        case let item as FoodLogEntry: return item.deletedAt != nil
        case let item as FavoriteRecipe: return item.deletedAt != nil
        case let item as DietaryPreference: return item.deletedAt != nil
        default: return false
        }
    }

    // MARK: Local-only predicates (mirror `_isLocalOnlyX`)

    /// A row is local-only iff it has never synced (`remoteVersion <= 0`), is not
    /// soft-deleted, has a non-empty id, and carries a non-blank identity field.
    static func isLocalOnlyInventory(_ item: Ingredient) -> Bool {
        item.remoteVersion <= 0
            && item.deletedAt == nil
            && !item.id.isEmpty
            && !item.name.trimmed.isEmpty
    }

    static func isLocalOnlyShopping(_ item: ShoppingItem) -> Bool {
        item.remoteVersion <= 0
            && item.deletedAt == nil
            && !item.id.isEmpty
            && !item.name.trimmed.isEmpty
    }

    static func isLocalOnlyRecipe(_ recipe: Recipe) -> Bool {
        recipe.remoteVersion <= 0
            && recipe.deletedAt == nil
            && !recipe.id.isEmpty
            && !recipe.name.trimmed.isEmpty
    }

    static func isLocalOnlyMealPlan(_ entry: MealPlanEntry) -> Bool {
        entry.remoteVersion <= 0
            && entry.deletedAt == nil
            && !entry.id.isEmpty
            && !entry.recipeId.trimmed.isEmpty
    }

    static func isLocalOnlyFoodLog(_ entry: FoodLogEntry) -> Bool {
        entry.remoteVersion <= 0
            && entry.deletedAt == nil
            && !entry.id.isEmpty
            && !entry.name.trimmed.isEmpty
    }

    static func isLocalOnlyFavoriteRecipe(_ favorite: FavoriteRecipe) -> Bool {
        favorite.remoteVersion <= 0
            && favorite.deletedAt == nil
            && !favorite.id.isEmpty
            && !favorite.recipeID.trimmed.isEmpty
    }

    static func isLocalOnlyDietaryPreference(_ preference: DietaryPreference) -> Bool {
        preference.remoteVersion <= 0
            && preference.deletedAt == nil
            && !preference.id.isEmpty
            && !preference.keyword.trimmed.isEmpty
    }

    // MARK: Generic core

    /// Shared merge: remote rows first, then the local-only rows absent remotely
    /// and allowed by the scope. Order is preserved (remote in load order, then
    /// the surviving locals in their original order).
    private static func merge<Element>(
        remote: [Element],
        local: [Element],
        scope: LocalUploadScope,
        entityType: SyncEntityType,
        id: (Element) -> String,
        isLocalOnly: (Element) -> Bool
    ) -> [Element] {
        let remoteIds = Set(remote.map(id))
        let survivingLocals = local.filter { element in
            isLocalOnly(element)
                && !remoteIds.contains(id(element))
                && scope.allows(entityType, id(element))
        }
        return remote + survivingLocals
    }
}
