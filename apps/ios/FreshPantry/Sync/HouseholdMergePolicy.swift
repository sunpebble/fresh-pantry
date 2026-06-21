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
///
/// The merge/patch/local-only/soft-delete rules are GENERIC over `SyncableEntity`
/// (ADR-0004) — the per-entity logic lives once in `merge`/`patch`. The named
/// wrappers below are thin call-site shims kept until the coordinator collapse
/// (Phase B) removes the last callers.
enum HouseholdMergePolicy {

    // MARK: Generic core (the rule, written once)

    /// Shared merge: remote rows first, then the local-only rows absent remotely
    /// and allowed by the scope. Order is preserved (remote in load order, then
    /// the surviving locals in their original order).
    static func merge<T: SyncableEntity>(
        remote: [T],
        local: [T],
        scope: LocalUploadScope,
        entityType: SyncEntityType
    ) -> [T] {
        let remoteIds = Set(remote.map(\.id))
        let survivingLocals = local.filter { element in
            element.isLocalOnly
                && !remoteIds.contains(element.id)
                && scope.allows(entityType, element.id)
        }
        return remote + survivingLocals
    }

    /// Applies an incremental remote delta onto the local snapshot: tombstones
    /// drop synced rows, upserts replace by id, unseen locals are kept.
    static func patch<T: SyncableEntity>(remoteDelta: [T], local: [T]) -> [T] {
        var deltaById: [String: T] = [:]
        var deletedIds = Set<String>()
        for delta in remoteDelta {
            if delta.deletedAt != nil {
                deltaById.removeValue(forKey: delta.id)
                deletedIds.insert(delta.id)
            } else {
                deltaById[delta.id] = delta
                deletedIds.remove(delta.id)
            }
        }
        var merged: [T] = []
        var seen = Set<String>()
        for item in local {
            if deletedIds.contains(item.id) { continue }
            if let delta = deltaById[item.id], delta.deletedAt == nil {
                merged.append(delta)
            } else if deltaById[item.id] == nil {
                merged.append(item)
            }
            seen.insert(item.id)
        }
        for (itemId, delta) in deltaById where !seen.contains(itemId) {
            merged.append(delta)
        }
        return merged
    }

    // MARK: Named shims (delegate to the generic core; removed in Phase B)

    static func mergeInventory(remote: [Ingredient], local: [Ingredient], scope: LocalUploadScope) -> [Ingredient] {
        merge(remote: remote, local: local, scope: scope, entityType: .inventoryItem)
    }

    static func mergeShopping(remote: [ShoppingItem], local: [ShoppingItem], scope: LocalUploadScope) -> [ShoppingItem] {
        merge(remote: remote, local: local, scope: scope, entityType: .shoppingItem)
    }

    static func mergeCustomRecipe(remote: [Recipe], local: [Recipe], scope: LocalUploadScope) -> [Recipe] {
        merge(remote: remote, local: local, scope: scope, entityType: .customRecipe)
    }

    static func mergeMealPlan(remote: [MealPlanEntry], local: [MealPlanEntry], scope: LocalUploadScope) -> [MealPlanEntry] {
        merge(remote: remote, local: local, scope: scope, entityType: .mealPlanEntry)
    }

    static func mergeFoodLog(remote: [FoodLogEntry], local: [FoodLogEntry], scope: LocalUploadScope) -> [FoodLogEntry] {
        merge(remote: remote, local: local, scope: scope, entityType: .foodLogEntry)
    }

    static func mergeFavoriteRecipe(remote: [FavoriteRecipe], local: [FavoriteRecipe], scope: LocalUploadScope) -> [FavoriteRecipe] {
        merge(remote: remote, local: local, scope: scope, entityType: .favoriteRecipe)
    }

    static func mergeDietaryPreference(remote: [DietaryPreference], local: [DietaryPreference], scope: LocalUploadScope) -> [DietaryPreference] {
        merge(remote: remote, local: local, scope: scope, entityType: .dietaryPreference)
    }

    static func patchInventory(remoteDelta: [Ingredient], local: [Ingredient]) -> [Ingredient] {
        patch(remoteDelta: remoteDelta, local: local)
    }

    static func patchShopping(remoteDelta: [ShoppingItem], local: [ShoppingItem]) -> [ShoppingItem] {
        patch(remoteDelta: remoteDelta, local: local)
    }

    static func patchCustomRecipe(remoteDelta: [Recipe], local: [Recipe]) -> [Recipe] {
        patch(remoteDelta: remoteDelta, local: local)
    }

    static func patchMealPlan(remoteDelta: [MealPlanEntry], local: [MealPlanEntry]) -> [MealPlanEntry] {
        patch(remoteDelta: remoteDelta, local: local)
    }

    static func patchFoodLog(remoteDelta: [FoodLogEntry], local: [FoodLogEntry]) -> [FoodLogEntry] {
        patch(remoteDelta: remoteDelta, local: local)
    }

    static func patchFavoriteRecipe(remoteDelta: [FavoriteRecipe], local: [FavoriteRecipe]) -> [FavoriteRecipe] {
        patch(remoteDelta: remoteDelta, local: local)
    }

    static func patchDietaryPreference(remoteDelta: [DietaryPreference], local: [DietaryPreference]) -> [DietaryPreference] {
        patch(remoteDelta: remoteDelta, local: local)
    }

    static func isLocalOnlyInventory(_ item: Ingredient) -> Bool { item.isLocalOnly }
    static func isLocalOnlyShopping(_ item: ShoppingItem) -> Bool { item.isLocalOnly }
    static func isLocalOnlyRecipe(_ recipe: Recipe) -> Bool { recipe.isLocalOnly }
    static func isLocalOnlyMealPlan(_ entry: MealPlanEntry) -> Bool { entry.isLocalOnly }
    static func isLocalOnlyFoodLog(_ entry: FoodLogEntry) -> Bool { entry.isLocalOnly }
    static func isLocalOnlyFavoriteRecipe(_ favorite: FavoriteRecipe) -> Bool { favorite.isLocalOnly }
    static func isLocalOnlyDietaryPreference(_ preference: DietaryPreference) -> Bool { preference.isLocalOnly }
}
