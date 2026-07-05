import Foundation

/// Editable prefill for storing a just-cooked dish as a leftover inventory row
/// (post-cook 剩菜入库). Pure value logic — the sheet binds to it and the saved
/// proposal flows through the canonical `IntakeController` add path — so the
/// field rules stay unit-testable without SwiftUI/SwiftData.
struct LeftoverDraft: Equatable, Sendable {
    /// Conservative fridge life for cooked food: food-safety guidance caps
    /// refrigerated leftovers at 3–4 days, so the prefill takes the cautious 3.
    static let defaultShelfLifeDays = 3
    /// Leftovers are tracked in servings — one cooked dish defaults to 1 份.
    static let unit = "份" // i18n:ignore data identity (stored unit value), not UI text

    /// User-editable dish name, prefilled from the recipe.
    var name: String
    /// Servings to store (份); floored to 1 at proposal time.
    var servings: Int
    /// Fridge days until expiry; floored to 1 at proposal time.
    var days: Int

    /// The prefill for `recipe`: its trimmed name, 1 份, refrigerated 3 days.
    static func from(recipe: Recipe) -> LeftoverDraft {
        LeftoverDraft(name: recipe.name.trimmed, servings: 1, days: defaultShelfLifeDays)
    }

    /// A leftover needs a non-blank name (mirrors the add form's submit gate).
    var canSave: Bool { !name.trimmed.isEmpty }

    /// Builds the intake proposal for this draft. Always a NEW row — never a
    /// merge: each cook is a distinct batch with its own freshness window, and
    /// merging into an older leftover row would silently inherit a stale
    /// expiry. Category is 其他 (the 5 canonical categories have no cooked-food
    /// bucket); storage is fridge, matching the 3-day refrigerated default.
    func proposal(now: Date = Date()) -> IntakeProposal {
        IntakeProposal(
            id: "leftover_\(Int(now.timeIntervalSince1970 * 1000))",
            name: name.trimmed,
            quantity: String(max(servings, 1)),
            unit: Self.unit,
            category: FoodCategories.other,
            storage: .fridge,
            shelfLifeDays: max(days, 1),
            action: .newRow,
            origin: .user
        )
    }
}
