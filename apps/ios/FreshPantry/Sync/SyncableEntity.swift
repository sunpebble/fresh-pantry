import Foundation

/// The contract that lets local⇄remote reconciliation be written ONCE. Every
/// synced model exposes its id, server version, soft-delete tombstone, and its
/// non-blank identity field, plus a way to stamp the uploaded version.
/// `HouseholdMergePolicy.merge`/`patch` and (P-B) the coordinator's apply
/// sequence are generic over this, so the soft-delete check and the
/// local-only / well-formed predicates stop being per-entity copies.
///
/// See ADR-0004. `hasSyncIdentity` is each model's non-blank identity field
/// (`name` / `recipeId` / `keyword` / `recipeID`) — the field whose blankness the
/// old `_isLocalOnlyX` helpers and the coordinator's decode filters checked
/// inline.
protocol SyncableEntity: Codable, Sendable {
    var id: String { get }
    var remoteVersion: Int { get }
    var deletedAt: Date? { get }
    var hasSyncIdentity: Bool { get }
    func withRemoteVersion(_ version: Int) -> Self
}

extension SyncableEntity {
    /// A row safe to persist / merge: non-empty id AND a non-blank identity field.
    /// Mirrors the per-entity decode filters the coordinator inlined.
    var isWellFormed: Bool { !id.isEmpty && hasSyncIdentity }

    /// Never-synced, not tombstoned, and well-formed — the `_isLocalOnlyX` rule.
    var isLocalOnly: Bool { remoteVersion <= 0 && deletedAt == nil && isWellFormed }
}

extension Ingredient: SyncableEntity {
    var hasSyncIdentity: Bool { !name.trimmed.isEmpty }
    func withRemoteVersion(_ version: Int) -> Ingredient { copyWith(remoteVersion: version) }
}

extension ShoppingItem: SyncableEntity {
    var hasSyncIdentity: Bool { !name.trimmed.isEmpty }
    func withRemoteVersion(_ version: Int) -> ShoppingItem { copyWith(remoteVersion: version) }
}

extension Recipe: SyncableEntity {
    var hasSyncIdentity: Bool { !name.trimmed.isEmpty }
    func withRemoteVersion(_ version: Int) -> Recipe { copyWith(remoteVersion: version) }
}

extension MealPlanEntry: SyncableEntity {
    var hasSyncIdentity: Bool { !recipeId.trimmed.isEmpty }
    func withRemoteVersion(_ version: Int) -> MealPlanEntry { copyWith(remoteVersion: version) }
}

extension FoodLogEntry: SyncableEntity {
    var hasSyncIdentity: Bool { !name.trimmed.isEmpty }
    func withRemoteVersion(_ version: Int) -> FoodLogEntry { copyWith(remoteVersion: version) }
}

extension FavoriteRecipe: SyncableEntity {
    var hasSyncIdentity: Bool { !recipeID.trimmed.isEmpty }
    func withRemoteVersion(_ version: Int) -> FavoriteRecipe { copyWith(remoteVersion: version) }
}

extension DietaryPreference: SyncableEntity {
    var hasSyncIdentity: Bool { !keyword.trimmed.isEmpty }
    func withRemoteVersion(_ version: Int) -> DietaryPreference { copyWith(remoteVersion: version) }
}
