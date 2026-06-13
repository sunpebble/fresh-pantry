import Foundation

/// Converts a cooked `Recipe` into reviewable inventory `DeductionProposal`
/// rows. Ported VERBATIM from `lib/services/deduction_proposal_factory.dart`.
///
/// `ProposalPlanner` owns fuzzy inventory matching; this factory owns the
/// recipe-completion adapter shape + the `d_<recipeId>_<index>` id scheme.
enum DeductionProposalFactory {
    static func forRecipe(
        _ recipe: Recipe,
        _ inventory: [Ingredient]
    ) -> [DeductionProposal] {
        var list: [DeductionProposal] = []
        for i in recipe.ingredients.indices {
            let ri = recipe.ingredients[i]
            let candidates = ProposalPlanner.fuzzyMatchInventoryRows(ri.name, inventory)
            if candidates.isEmpty {
                list.append(
                    DeductionProposal.empty(
                        id: "d_\(recipe.id)_\(i)",
                        recipeIngredientName: ri.name,
                        requiredQty: ri.displayAmount
                    )
                )
            } else {
                list.append(
                    DeductionProposal(
                        id: "d_\(recipe.id)_\(i)",
                        recipeIngredientName: ri.name,
                        requiredQty: ri.displayAmount,
                        candidates: candidates,
                        chosenIndex: candidates.first!.inventoryRowIndex,
                        deductAmount: initialDeductAmount(ri, candidates.first!)
                    )
                )
            }
        }
        return list
    }

    /// Picks the default deduct amount for a matched recipe ingredient.
    ///
    /// Uses the recipe's real numeric magnitude only when it can be reconciled
    /// with the chosen inventory row's unit; otherwise falls back to 1 (a safe
    /// "used one" default) instead of blindly deducting the raw recipe number
    /// against a different unit. ALWAYS returns a parseable number so a deduction
    /// can never silently apply zero.
    private static func initialDeductAmount(
        _ ri: RecipeIngredient,
        _ chosen: DeductionCandidate
    ) -> String {
        let (magnitude, recipeUnit) = parseMagnitudeUnit(ri)
        guard let magnitude, magnitude > 0 else { return "1" }
        let rowUnit = chosen.inventoryRowUnit.trimmed
        let unitsCompatible = recipeUnit.isEmpty || rowUnit.isEmpty || recipeUnit == rowUnit
        if !unitsCompatible { return "1" }
        return QuantityText.formatQuantity(magnitude)
    }

    /// The numeric magnitude + unit straight off the structured ingredient. The
    /// quantity is already a `Double?` (no string parsing); the range upper bound
    /// is irrelevant for an initial deduction (we deduct the lower bound).
    private static func parseMagnitudeUnit(_ ri: RecipeIngredient) -> (Double?, String) {
        (ri.quantity, ri.unit?.trimmed ?? "")
    }
}
