import Foundation

/// Editable state for the manual add-ingredient form, plus the smart-default
/// autofill and the `IntakeProposal` building. Kept as an `@Observable`
/// view-model (not in the View) so the autofill + proposal logic is unit
/// testable without SwiftUI.
///
/// Autofill rule (mirrors the Flutter add form): when the user commits a name,
/// look it up in `FoodKnowledge`; for each of category / storage / shelf-life
/// that the user has NOT explicitly overridden, adopt the smart default. A field
/// the user touched is never silently overwritten.
@Observable
@MainActor
final class AddIngredientForm {
    var name: String = ""
    var quantity: String = "1"
    var unit: String = "个"
    var category: String = FoodCategories.other
    var storage: IconType = .fridge
    /// nil = no expiry (留空表示不过期).
    var shelfLifeDays: Int?
    /// Product barcode (EAN/UPC) when the form was seeded from a barcode scan;
    /// nil for a hand-started add. Flows onto the proposal → resulting row so the
    /// scanned product keeps its barcode for later detail lookups.
    var barcode: String?

    /// Per-field "user touched this" flags — once set, autofill leaves the field
    /// alone so a later name change can't stomp a deliberate choice.
    private(set) var categoryEdited = false
    private(set) var storageEdited = false
    private(set) var shelfLifeEdited = false

    /// The shelf-life quick-select presets surfaced in the form.
    let shelfLifePresets = FoodKnowledge.shelfLifePresets // [3, 7, 14, 30]

    /// The unit options surfaced in the picker (knowledge-base units + a couple
    /// the picker blueprint lists), de-duplicated, current unit appended so a
    /// custom value still shows as selected.
    var unitOptions: [String] {
        var options = ["个", "只", "把", "盒", "袋", "瓶", "罐", "份"]
        for unit in FoodKnowledge.units where !options.contains(unit) {
            options.append(unit)
        }
        if !unit.trimmed.isEmpty && !options.contains(unit) {
            options.append(unit)
        }
        return options
    }

    // MARK: Edits

    func setCategory(_ value: String) {
        category = FoodCategories.dropdownValue(value)
        categoryEdited = true
    }

    func setStorage(_ value: IconType) {
        storage = value
        storageEdited = true
    }

    func setShelfLife(_ days: Int?) {
        shelfLifeDays = days.map { Swift.max($0, 1) }
        shelfLifeEdited = true
    }

    func setUnit(_ value: String) {
        let trimmed = value.trimmed
        unit = trimmed.isEmpty ? unit : trimmed
    }

    /// Applies `FoodKnowledge` smart defaults for the current name to any field
    /// the user hasn't overridden. Called when the name field commits/blurs.
    func applySmartDefaults() {
        guard let defaults = FoodKnowledge.lookup(name) else { return }
        if !categoryEdited {
            category = FoodCategories.dropdownValue(defaults.category)
        }
        if !storageEdited {
            storage = defaults.storage
        }
        if !shelfLifeEdited {
            shelfLifeDays = defaults.shelfLifeDays
        }
    }

    /// Seeds the form from a frequently-added item (常购食材 quick-fill), pinning
    /// category/storage/shelf-life as user-set so a later name-commit autofill
    /// can't stomp them. Mirrors the Flutter `_applyFrequentItem`.
    func applyFrequentItem(_ item: FrequentItem) {
        name = item.name
        setCategory(item.category)
        setStorage(item.storage)
        setUnit(item.unit)
        if let days = item.shelfLifeDays { setShelfLife(days) }
    }

    // MARK: Barcode prefill

    /// Seeds the form from an Open Food Facts barcode lookup. Pure mapping
    /// (no SwiftUI / network) so it's unit-testable: `displayName → name`,
    /// `category`, `storage`, `shelfLifeDays`, and the scanned `barcode` (always
    /// set, even when `details` is nil so the user can still add manually). All
    /// three smart-default fields are marked edited so a later name-commit autofill
    /// can't stomp the OFF values. A blank `displayName` leaves `name` empty
    /// (the OFF result was unusable) but the barcode is still recorded.
    func prefill(from details: FoodDetails?, barcode: String) {
        let trimmedBarcode = barcode.trimmed
        self.barcode = trimmedBarcode.isEmpty ? nil : trimmedBarcode

        guard let details else { return }

        let trimmedName = details.displayName.trimmed
        if !trimmedName.isEmpty {
            name = trimmedName
        }
        // OFF details are authoritative here — pin them as user-edited so a later
        // name-commit autofill doesn't overwrite the looked-up category/storage/shelf.
        setCategory(details.category)
        setStorage(details.storage)
        setShelfLife(details.shelfLifeDays)
    }

    // MARK: Validation / proposal building

    /// The form can produce a proposal only with a non-empty name.
    var canSubmit: Bool { !name.trimmed.isEmpty }

    /// Builds the single intake proposal for this form against the live
    /// inventory, routing through the P4 `IntakeProposalFactory` so the
    /// merge-vs-new-batch default + merge-target label are computed by the same
    /// rules the AI/shopping flows use. `origin = .user` (hand-filled).
    func buildProposal(inventory: [Ingredient]) -> IntakeProposal {
        let draft = IngredientDraft(
            id: "manual_\(Int(Date().timeIntervalSince1970 * 1000))",
            name: .user(name.trimmed),
            quantity: .user(normalizedQuantity),
            unit: .user(unit.trimmed.isEmpty ? "个" : unit.trimmed),
            category: .user(FoodCategories.dropdownValue(category)),
            storage: .user(storage),
            shelfLifeDays: .user(shelfLifeDays)
        )
        // fromDrafts resolves the default action against inventory and owns the
        // merge-target hint; re-tag origin as .user (the factory defaults to .ai).
        let proposal = IntakeProposalFactory.fromDrafts([draft], inventory).first!
        let trimmedBarcode = barcode?.trimmed
        return IntakeProposal(
            id: proposal.id,
            name: proposal.name,
            quantity: proposal.quantity,
            unit: proposal.unit,
            category: proposal.category,
            storage: proposal.storage,
            shelfLifeDays: proposal.shelfLifeDays,
            action: proposal.action,
            mergeTargetId: proposal.mergeTargetId,
            mergeTargetLabel: proposal.mergeTargetLabel,
            origin: .user,
            barcode: (trimmedBarcode?.isEmpty == false) ? trimmedBarcode : nil
        )
    }

    /// Trimmed quantity, falling back to "1" when blank / non-positive-looking.
    private var normalizedQuantity: String {
        let trimmed = quantity.trimmed
        if trimmed.isEmpty { return "1" }
        return trimmed
    }
}
