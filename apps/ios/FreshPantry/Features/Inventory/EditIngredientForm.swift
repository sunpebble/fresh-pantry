import Foundation

/// Editable state for the EDIT-ingredient form (modifying an existing inventory
/// row), mirroring the Flutter add/edit screen's edit mode
/// (`add_ingredient_screen.dart`, `_isEditing`).
///
/// Unlike the add form it carries an explicit `expiryDate` anchor: an untouched
/// edit keeps the row's original expiry, changing the shelf-life recomputes it to
/// today + N days, and 不过期 clears it. Kept as an `@Observable` view-model so the
/// seeding + recompute + build logic is unit-testable without SwiftUI. Identity and
/// provenance (id / addedAt / barcode / imageUrl / sync triplet) are preserved from
/// the original; only the user-editable fields change. Freshness/state/label are
/// recomputed by `InventoryStore.update` on apply.
@Observable
@MainActor
final class EditIngredientForm {
    /// The row being edited — its unchanged fields resolve the row on save (so a
    /// rename still finds it) and its provenance is preserved into the result.
    let original: Ingredient

    var name: String
    var quantity: String
    var unit: String
    var category: String
    var storage: IconType
    /// User-defined tags, seeded from the original row. Canonicalized by
    /// `Ingredient.normalizeTags` on `buildEdited` (the editor holds raw input).
    var tags: [String]
    /// nil = 不过期 (no expiry). Drives the shelf-life chip selection.
    private(set) var shelfLifeDays: Int?
    /// The resolved expiry anchor: the original date until the user changes the
    /// shelf-life (then today + N days), or nil for 不过期.
    private(set) var expiryDate: Date?

    /// Quick-select presets surfaced in the form ([3, 7, 14, 30]).
    let shelfLifePresets = FoodKnowledge.shelfLifePresets

    init(_ item: Ingredient) {
        original = item
        name = item.name
        quantity = item.quantity
        unit = item.unit.trimmed.isEmpty ? "个" : item.unit // i18n:ignore domain unit-default identity, not UI text
        category = FoodCategories.dropdownValue(item.category)
        storage = item.storage
        tags = item.tags
        expiryDate = item.expiryDate
        // Seed shelf-life: saved value, else derive from the remaining window
        // (mirrors Flutter's `initial.shelfLifeDays ?? daysUntilExpiry(expiry)`).
        if let saved = item.shelfLifeDays, saved > 0 {
            shelfLifeDays = saved
        } else if let expiry = item.expiryDate {
            let days = ExpiryCalculator.daysUntilExpiry(expiry)
            shelfLifeDays = days > 0 ? days : nil
        } else {
            shelfLifeDays = nil
        }
    }

    /// Unit options surfaced in the picker (knowledge-base units + a couple the
    /// picker blueprint lists), de-duplicated, current unit appended so a custom
    /// value still shows as selected. Mirrors `AddIngredientForm.unitOptions`.
    var unitOptions: [String] {
        var options = ["个", "只", "把", "盒", "袋", "瓶", "罐", "份"] // i18n:ignore domain unit-default identity, not UI text
        for unit in FoodKnowledge.units where !options.contains(unit) {
            options.append(unit)
        }
        if !unit.trimmed.isEmpty && !options.contains(unit) {
            options.append(unit)
        }
        return options
    }

    // MARK: Edits

    func setUnit(_ value: String) {
        let trimmed = value.trimmed
        if !trimmed.isEmpty { unit = trimmed }
    }

    func setCategory(_ value: String) {
        category = FoodCategories.dropdownValue(value)
    }

    func setStorage(_ value: IconType) {
        storage = value
    }

    /// Sets the shelf-life and recomputes the expiry anchor to today + N days
    /// (nil / non-positive = 不过期 → clears the expiry). Mirrors Flutter
    /// `_setShelfDays` (expiry = today + days).
    func setShelfLife(_ days: Int?, now: Date = Date()) {
        guard let days, days > 0 else {
            shelfLifeDays = nil
            expiryDate = nil
            return
        }
        shelfLifeDays = days
        let today = Calendar.current.startOfDay(for: now)
        expiryDate = Calendar.current.date(byAdding: .day, value: days, to: today)
    }

    // MARK: Validation / build

    /// Editable with a non-empty name and a quantity that is blank (→ "1") or a
    /// positive number — rejects 0 / negative / a lone "." (mirrors the Flutter
    /// save guard).
    var canSubmit: Bool {
        guard !name.trimmed.isEmpty else { return false }
        let quantityText = quantity.trimmed
        if quantityText.isEmpty { return true }
        guard let parsed = Double(quantityText) else { return false }
        return parsed > 0
    }

    /// Builds the edited row, preserving identity + provenance (id / addedAt /
    /// barcode / imageUrl / sync triplet) and carrying the new user fields. The
    /// store recomputes freshness/state/label from the (new) expiry on apply, so
    /// those are seeded from the original here.
    func buildEdited() -> Ingredient {
        let quantityText = quantity.trimmed
        return Ingredient(
            id: original.id,
            name: name.trimmed,
            quantity: quantityText.isEmpty ? "1" : quantityText,
            unit: unit.trimmed.isEmpty ? "个" : unit.trimmed, // i18n:ignore domain unit-default identity, not UI text
            imageUrl: original.imageUrl,
            freshnessPercent: original.freshnessPercent,
            state: original.state,
            expiryLabel: original.expiryLabel,
            category: FoodCategories.dropdownValue(category),
            barcode: original.barcode,
            storage: storage,
            expiryDate: expiryDate,
            addedAt: original.addedAt,
            shelfLifeDays: shelfLifeDays,
            tags: Ingredient.normalizeTags(tags),
            remoteVersion: original.remoteVersion,
            clientUpdatedAt: original.clientUpdatedAt,
            deletedAt: original.deletedAt
        )
    }
}
