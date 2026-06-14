import Foundation

/// Holds an ingredient name until the Recipes tab can filter to dishes that use
/// it — backs the 临期看板「→做这道菜」shortcut (#18).
///
/// Producer = `ExpiringView`'s per-item action; consumers split: `RootView`
/// OBSERVES `pendingIngredient` to switch to the 食谱 tab (it must NOT consume),
/// while `RecipesView` CONSUMES it (sets the search to that ingredient on the
/// 探索 tab). Mirrors `NotificationTapRouter`'s pending/consume/clear pattern,
/// including the cold-start `.task(id:)` timing note.
@Observable
@MainActor
final class RecipeFilterRouter {
    /// Ingredient name awaiting consumption; nil when none pending.
    private(set) var pendingIngredient: String?

    func capture(ingredient name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingIngredient = trimmed.isEmpty ? nil : trimmed
    }

    /// One-shot read: returns the pending ingredient and clears it.
    @discardableResult
    func consume() -> String? {
        let value = pendingIngredient
        pendingIngredient = nil
        return value
    }

    func clear() { pendingIngredient = nil }
}
