import Foundation

/// One ingredient row inside a `RecipeDraft`. Transient.
struct RecipeIngredientDraft {
    var name: DraftField<String>
    var amount: DraftField<String>

    init(name: DraftField<String>, amount: DraftField<String>) {
        self.name = name
        self.amount = amount
    }

    /// quantity/quantityMax/unit/note are derived from the free-text `amount`
    /// via the lossless `RecipeIngredient.fromAmountText` parser (number/range +
    /// unit, or a fuzzy `note`).
    func toIngredient() -> RecipeIngredient {
        RecipeIngredient.fromAmountText(name: name.value, amount: amount.value)
    }
}

/// AI/manual draft for an imported/authored recipe; converts to a `Recipe`.
/// Transient (no equality/JSON).
struct RecipeDraft {
    var sourceUrl: String?
    var name: DraftField<String>
    var category: DraftField<String>
    var cookingMinutes: DraftField<Int>
    var difficulty: DraftField<Int>
    var description: DraftField<String>
    var imageUrl: DraftField<String?>
    var ingredients: [RecipeIngredientDraft]
    var steps: [DraftField<String>]

    init(
        sourceUrl: String?,
        name: DraftField<String>,
        category: DraftField<String>,
        cookingMinutes: DraftField<Int>,
        difficulty: DraftField<Int>,
        description: DraftField<String>,
        imageUrl: DraftField<String?>,
        ingredients: [RecipeIngredientDraft],
        steps: [DraftField<String>]
    ) {
        self.sourceUrl = sourceUrl
        self.name = name
        self.category = category
        self.cookingMinutes = cookingMinutes
        self.difficulty = difficulty
        self.description = description
        self.imageUrl = imageUrl
        self.ingredients = ingredients
        self.steps = steps
    }

    /// Mirrors Dart `toRecipe`: id from generator or `custom_<ms>`.
    func toRecipe(idGenerator: (() -> String)? = nil) -> Recipe {
        let id = idGenerator?() ?? "custom_\(Date.nowMilliseconds)"
        return Recipe(
            id: id,
            name: name.value,
            category: category.value,
            difficulty: difficulty.value,
            cookingMinutes: cookingMinutes.value,
            description: description.value,
            ingredients: ingredients.map { $0.toIngredient() },
            steps: steps.map { $0.value },
            tags: [],
            imageUrl: imageUrl.value
        )
    }
}
