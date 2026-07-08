import Foundation

/// ADR-0001 identity rule: identity is `name × unit × StorageArea ×
/// (Batch for Perishables)`. The SINGLE arbiter of merge-vs-new-batch. Ported
/// verbatim from `lib/models/ingredient_identity.dart`.
///
/// Normalization asymmetry (intentional, matches Flutter):
///   - name match: trim + lowercase (case-insensitive)
///   - unit match: trim only (CASE-SENSITIVE)
///   - storage: exact enum match
///   - a matched row with a non-numeric quantity returns -1 (merging would
///     silently discard its stock)
enum IngredientIdentity {
    /// A perishable always creates a new batch. Decided by BOTH the category
    /// alias-normalization AND the name-keyword knowledge base.
    static func isPerishable(category: String?, name: String) -> Bool {
        FoodCategories.isPerishable(category) || FoodKnowledge.isPerishableName(name)
    }

    /// Index of the inventory row an intake should merge into, or -1 = new row.
    static func resolveMergeTarget(
        name: String,
        unit: String,
        storage: IconType,
        category: String? = nil,
        inventory: [Ingredient]
    ) -> Int {
        if isPerishable(category: category, name: name) { return -1 }
        let normalizedName = name.trimmed.lowercased()
        let normalizedUnit = unit.trimmed
        if normalizedName.isEmpty || normalizedUnit.isEmpty { return -1 }
        for (i, row) in inventory.enumerated() {
            if row.name.trimmed.isEmpty { continue }
            if row.name.trimmed.lowercased() != normalizedName { continue }
            if row.unit.trimmed != normalizedUnit { continue }
            if row.storage != storage { continue }
            if QuantityText.numeric(row.quantity) == nil { return -1 }
            return i
        }
        return -1
    }
}
