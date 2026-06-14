import Foundation

/// Pure, SwiftUI-free editable model + validation for the custom-recipe form.
/// Kept separate from the View so the validation + recipe-building logic is unit
/// testable. Mirrors the Dart form's `_validateBasic` / `_validateIngredients`
/// and the `_saveRecipe` build.
struct CustomRecipeDraft: Equatable {
    /// One editable ingredient row (name + numeric quantity + unit).
    struct IngredientRow: Equatable, Identifiable {
        let id: UUID
        var name: String
        var quantity: String
        var unit: String

        init(id: UUID = UUID(), name: String = "", quantity: String = "", unit: String = "g") {
            self.id = id
            self.name = name
            self.quantity = quantity
            self.unit = unit
        }
    }

    /// One editable step row (multi-line text).
    struct StepRow: Equatable, Identifiable {
        let id: UUID
        var text: String

        init(id: UUID = UUID(), text: String = "") {
            self.id = id
            self.text = text
        }
    }

    /// Which field an inline error attaches to (the form anchors/scrolls to the
    /// first one). `ingredients` carries a combined message (missing rows /
    /// names / amounts).
    enum Field: Equatable {
        case name
        case category
        case cookingMinutes
        case difficulty
        case ingredients
        case steps
    }

    var name: String
    var category: String
    var cookingMinutes: String
    var difficulty: Int
    var description: String
    var ingredients: [IngredientRow]
    var steps: [StepRow]
    /// Cover image URL — a `file://` path for a locally-picked cover, or a remote
    /// `http(s)` URL for an AI-imported one. nil ⇒ no cover (the category hero
    /// renders). Persisted into `Recipe.imageUrl` on build.
    var imageUrl: String?
    /// User-defined free-text labels (「快手」「宴客」「孩子爱吃」…) for cross-cutting
    /// grouping beyond category. Held as the user types them (display casing kept);
    /// `buildRecipe` canonicalizes via `Ingredient.normalizeTags` on save — the same
    /// single-source shaping the inventory tags use.
    var tags: [String]

    init(
        name: String = "",
        category: String = "家常",
        cookingMinutes: String = "",
        difficulty: Int = 3,
        description: String = "",
        ingredients: [IngredientRow] = [IngredientRow()],
        steps: [StepRow] = [StepRow()],
        imageUrl: String? = nil,
        tags: [String] = []
    ) {
        self.name = name
        self.category = category
        self.cookingMinutes = cookingMinutes
        self.difficulty = difficulty
        self.description = description
        self.ingredients = ingredients
        self.steps = steps
        self.imageUrl = imageUrl
        self.tags = tags
    }

    /// Seeds the draft from an existing recipe (edit mode). The structured
    /// quantity (`Double?`) renders into the text field via
    /// `QuantityText.formatQuantity`; a range renders as "lower-upper" so it
    /// round-trips (else `completeIngredients` would collapse it to the lower
    /// bound on save); a fuzzy amount (`note`) drops into the quantity text with
    /// no unit so the row stays editable and round-trips on save.
    init(recipe: Recipe) {
        let rows = recipe.ingredients.map { ri -> IngredientRow in
            let quantityText: String
            if let q = ri.quantity {
                if let max = ri.quantityMax {
                    quantityText = QuantityText.formatQuantity(q) + "-" + QuantityText.formatQuantity(max)
                } else {
                    quantityText = QuantityText.formatQuantity(q)
                }
            } else {
                quantityText = ri.note ?? ""
            }
            return IngredientRow(name: ri.name, quantity: quantityText, unit: ri.unit ?? "")
        }
        let steps = recipe.steps.map { StepRow(text: $0) }
        self.init(
            name: recipe.name,
            category: recipe.category.trimmed.isEmpty ? "家常" : recipe.category,
            cookingMinutes: String(recipe.cookingMinutes),
            difficulty: recipe.difficulty < 1 || recipe.difficulty > 5 ? 3 : recipe.difficulty,
            description: recipe.description,
            ingredients: rows.isEmpty ? [IngredientRow()] : rows,
            steps: steps.isEmpty ? [StepRow()] : steps,
            imageUrl: recipe.imageUrl,
            tags: recipe.tags
        )
    }

    /// Seeds the editable draft from an AI-parsed `RecipeDraft` (URL import).
    /// Mirrors the Dart `recipeDraftToApplyResult` mapping: scalar fields copied
    /// straight across; each ingredient `amount` string split into quantity/unit
    /// via `splitAmount` (numeric prefix + a KNOWN unit only — an unknown
    /// remainder folds back into the quantity text rather than producing junk
    /// units). Empty ingredient/step lists fall back to one blank row so the form
    /// stays editable. `imageUrl` (when the parse found a cover) is carried through
    /// so the form's cover section shows the AI-imported cover; a blank URL → nil.
    init(parsed draft: RecipeDraft) {
        let rows = draft.ingredients.map { ingredient -> IngredientRow in
            let split = CustomRecipeDraft.splitAmount(ingredient.amount.value)
            return IngredientRow(name: ingredient.name.value, quantity: split.quantity, unit: split.unit)
        }
        let stepRows = draft.steps.map { StepRow(text: $0.value) }
        let parsedImageUrl = draft.imageUrl.value?.trimmed
        self.init(
            name: draft.name.value,
            category: draft.category.value.trimmed.isEmpty ? "家常" : draft.category.value,
            cookingMinutes: String(draft.cookingMinutes.value),
            difficulty: draft.difficulty.value < 1 || draft.difficulty.value > 5 ? 3 : draft.difficulty.value,
            description: draft.description.value,
            ingredients: rows.isEmpty ? [IngredientRow()] : rows,
            steps: stepRows.isEmpty ? [StepRow()] : stepRows,
            imageUrl: (parsedImageUrl?.isEmpty == false) ? parsedImageUrl : nil
        )
    }

    /// Splits an AI amount string ("3 个", "1.5kg", "2-3根", "少许") into a
    /// `(quantity, unit)` pair for the editable rows. Ported VERBATIM from the
    /// Dart `appliedIngredientRowFromDraft`:
    ///   * leading numeric token = `^(\d+(?:[./\-]\d+)?)\s*(.*)$` (fraction /
    ///     range / decimal / int);
    ///   * the remainder becomes the unit ONLY when it is a known preset unit;
    ///   * an unknown remainder folds back into the quantity text so we never
    ///     emit a junk unit like "/2个" or "-3根";
    ///   * a non-numeric amount ("少许") stays as quantity text with no unit.
    static func splitAmount(_ rawAmount: String) -> (quantity: String, unit: String) {
        let amount = rawAmount.trimmed
        if amount.isEmpty { return ("", "") }

        guard let match = amountRegex.firstMatch(
            in: amount,
            range: NSRange(amount.startIndex..., in: amount)
        ),
        let qtyRange = Range(match.range(at: 1), in: amount)
        else {
            // Descriptive amount (no numeric prefix) — keep as quantity text.
            return (amount, "")
        }

        let qty = String(amount[qtyRange])
        let remainder: String
        if let remRange = Range(match.range(at: 2), in: amount) {
            remainder = String(amount[remRange]).trimmed
        } else {
            remainder = ""
        }

        let unit = RecipePresets.units.contains(remainder) ? remainder : ""
        let quantityText = unit.isEmpty && !remainder.isEmpty ? "\(qty)\(remainder)" : qty
        return (quantityText, unit)
    }

    /// `^(\d+(?:[./\-]\d+)?)\s*(.*)$` — leading quantity (fraction/range/decimal/
    /// int) + optional remainder. Matches the Dart `_quantityRe`.
    private static let amountRegex = try! NSRegularExpression(
        pattern: #"^(\d+(?:[./\-]\d+)?)\s*(.*)$"#,
        options: [.dotMatchesLineSeparators]
    )

    // MARK: Reordering (up/down nudges)

    /// Moves the ingredient at `index` by `offset` rows (typically ±1), swapping
    /// with the neighbor. Out-of-bounds targets are a no-op so callers can wire
    /// disabled-edge buttons defensively. Pure model mutation (the form persists
    /// the reordered draft on Save), kept here to stay unit-testable.
    mutating func moveIngredient(from index: Int, by offset: Int) {
        let target = index + offset
        guard ingredients.indices.contains(index), ingredients.indices.contains(target) else { return }
        ingredients.swapAt(index, target)
    }

    /// Moves the step at `index` by `offset` rows (typically ±1), swapping with the
    /// neighbor. Out-of-bounds targets are a no-op. The step badges renumber for
    /// free since the form labels by enumerated offset.
    mutating func moveStep(from index: Int, by offset: Int) {
        let target = index + offset
        guard steps.indices.contains(index), steps.indices.contains(target) else { return }
        steps.swapAt(index, target)
    }

    // MARK: Validation

    /// The trimmed, non-empty cooking steps (the ones that survive to the recipe).
    var trimmedSteps: [String] {
        steps.map { $0.text.trimmed }.filter { !$0.isEmpty }
    }

    /// The complete ingredient rows (name AND quantity-or-unit present), deduped
    /// at build via `RecipeIngredient`. The text quantity is parsed into the
    /// lossless model: a number (or "6-15" range) → `quantity`/`quantityMax` +
    /// `unit`; a non-numeric quantity ("少许") → `note` (no unit). Mirrors Dart
    /// `_completeIngredients`.
    var completeIngredients: [RecipeIngredient] {
        ingredients.compactMap { row in
            let name = row.name.trimmed
            let quantityText = row.quantity.trimmed
            let unitText = row.unit.trimmed
            if name.isEmpty { return nil }
            if quantityText.isEmpty && unitText.isEmpty { return nil }
            let unit: String? = unitText.isEmpty ? nil : unitText
            if quantityText.isEmpty {
                // Unit only, no magnitude — keep the unit, no number.
                return RecipeIngredient(name: name, unit: unit)
            }
            if let range = CustomRecipeDraft.parseRangeText(quantityText) {
                return RecipeIngredient(
                    name: name, quantity: range.lower, quantityMax: range.upper, unit: unit
                )
            }
            if let value = Double(quantityText) {
                return RecipeIngredient(name: name, quantity: value, unit: unit)
            }
            // Non-numeric quantity ("少许") → fuzzy note; the unit text (if any)
            // is folded in so nothing is dropped.
            let note = unit.map { "\(quantityText)\($0)" } ?? quantityText
            return RecipeIngredient(name: name, note: note)
        }
    }

    /// Parses a "lower-upper" numeric range text ("6-15", "2-3") into bounds.
    static func parseRangeText(_ input: String) -> (lower: Double, upper: Double)? {
        let parts = input.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let lower = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let upper = Double(parts[1].trimmingCharacters(in: .whitespaces))
        else { return nil }
        return (lower, upper)
    }

    /// Per-field error messages. Empty dictionary ⇒ valid. Mirrors the Dart
    /// validators: name/category non-empty; cookingMinutes a positive int;
    /// difficulty 1–5; at least one COMPLETE ingredient with neither a name nor a
    /// quantity dangling alone; at least one non-empty step.
    func validate() -> [Field: String] {
        var errors: [Field: String] = [:]

        if name.trimmed.isEmpty {
            errors[.name] = "请填入食谱名称"
        }
        if category.trimmed.isEmpty {
            errors[.category] = "请选择分类"
        }
        if let minutes = Int(cookingMinutes.trimmed), minutes > 0 {
            // valid
        } else {
            errors[.cookingMinutes] = "请输入大于 0 的分钟数"
        }
        if difficulty < 1 || difficulty > 5 {
            errors[.difficulty] = "请选择 1-5 颗星"
        }
        if let message = ingredientsError() {
            errors[.ingredients] = message
        }
        if trimmedSteps.isEmpty {
            errors[.steps] = "至少添加一个步骤"
        }

        return errors
    }

    var isValid: Bool { validate().isEmpty }

    /// Ingredient-section error string (nil when valid). A name without a
    /// quantity OR a quantity without a name is an error; a row with neither is
    /// just blank padding. At least one complete row is required.
    private func ingredientsError() -> String? {
        var hasAnyText = false
        var hasComplete = false
        var missingName = false
        var missingAmount = false

        for row in ingredients {
            let name = row.name.trimmed
            // Only a non-empty quantity counts as "amount" — the unit always has a
            // preselected default and isn't user-entered text (mirrors Dart).
            let hasAmount = !row.quantity.trimmed.isEmpty
            if !name.isEmpty || hasAmount { hasAnyText = true }
            if !name.isEmpty && hasAmount {
                hasComplete = true
            } else if name.isEmpty && hasAmount {
                missingName = true
            } else if !name.isEmpty && !hasAmount {
                missingAmount = true
            }
        }

        var parts: [String] = []
        if !hasComplete && !hasAnyText { parts.append("至少一种食材") }
        if missingName { parts.append("食材名称") }
        if missingAmount { parts.append("食材用量") }
        return parts.isEmpty ? nil : parts.joined(separator: "、")
    }

    // MARK: AI 解析覆盖

    /// Merge applied when an AI URL parse lands on the form: the parsed draft
    /// wins wholesale, EXCEPT a parse that found NO cover keeps the form's
    /// already-picked one (Dart `_applyRecipeDraft` parity — the parse knows
    /// nothing about that cover, so it must not silently drop it). Also reports
    /// the cover the merge displaced so the caller can delete a local `file://`
    /// orphan (`RecipeCoverStore.delete` ignores remote URLs itself).
    static func mergingParsed(
        _ parsed: CustomRecipeDraft,
        over current: CustomRecipeDraft
    ) -> (merged: CustomRecipeDraft, replacedCover: String?) {
        var merged = parsed
        if merged.imageUrl == nil {
            merged.imageUrl = current.imageUrl
        }
        // The parse knows nothing about tags (same as the cover) — keep the form's
        // already-entered tags rather than letting an empty parse silently drop them.
        if merged.tags.isEmpty {
            merged.tags = current.tags
        }
        let replaced = current.imageUrl != nil && current.imageUrl != merged.imageUrl
            ? current.imageUrl
            : nil
        return (merged, replaced)
    }

    // MARK: Build

    /// Builds the persisted `Recipe`. A NEW recipe (`existing == nil`) gets a
    /// LOWERCASED UUID id — NOT a `custom_<ms>` id — so it reconciles cleanly with
    /// the server row (the gateway/coordinator match by id and only write UUID
    /// ids remotely; a non-UUID id would never match). An edit preserves the
    /// existing id, tags, and sync metadata.
    func buildRecipe(existing: Recipe? = nil) -> Recipe {
        Recipe(
            id: existing?.id ?? UUID().uuidString.lowercased(),
            name: name.trimmed,
            category: category.trimmed,
            difficulty: difficulty,
            cookingMinutes: Int(cookingMinutes.trimmed) ?? 0,
            description: description.trimmed,
            ingredients: completeIngredients,
            steps: trimmedSteps,
            // Canonicalize on save (single source: `Ingredient.normalizeTags`) so a
            // new recipe carries the user's tags and an edit honors their changes —
            // the seed-from-existing path keeps an untouched edit identical.
            tags: Ingredient.normalizeTags(tags),
            imageUrl: imageUrl?.trimmed.isEmpty == false ? imageUrl?.trimmed : nil,
            remoteVersion: existing?.remoteVersion ?? 0,
            clientUpdatedAt: existing?.clientUpdatedAt,
            deletedAt: existing?.deletedAt
        )
    }
}
