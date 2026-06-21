import Foundation

// Ephemeral AI/intake review proposals — NOT persisted, no sync triplet; they
// drive the Review UI. `IntakeProposal` and `DeductionProposal` both carry
// `id` + `selected`, but the Review screens use them as concrete types, never
// polymorphically, so no shared `Proposal` protocol earns its keep.

/// Intake proposal (one parsed ingredient row awaiting confirmation).
///
/// `mergeTargetId` corresponds to the inventory list INDEX-derived row id at
/// proposal-compute time; callers MUST re-resolve via `IngredientIdentity`
/// before applying (lists reorder/shrink via sync).
struct IntakeProposal {
    var id: String
    var name: String
    var quantity: String
    var unit: String
    var category: String?
    var storage: IconType
    var shelfLifeDays: Int?
    var action: IntakeAction
    var mergeTargetId: String?
    var mergeTargetLabel: String?
    /// Origin of the data before user edits; immutable through `copyWith`.
    var origin: FieldOrigin
    var userEdited: Bool
    var selected: Bool
    /// Product barcode (EAN/UPC) when this proposal came from a barcode scan;
    /// nil otherwise. Carried onto the resulting NEW inventory row so a later
    /// detail lookup keys off the barcode directly. A merge keeps the existing
    /// row's barcode (no overwrite).
    var barcode: String?
    /// User-defined tags to stamp onto a resulting NEW inventory row (manual add).
    /// A merge keeps the existing batch's tags (no overwrite), mirroring barcode.
    var tags: [String]

    init(
        id: String,
        name: String,
        quantity: String,
        unit: String,
        category: String?,
        storage: IconType,
        shelfLifeDays: Int?,
        action: IntakeAction = .newRow,
        mergeTargetId: String? = nil,
        mergeTargetLabel: String? = nil,
        origin: FieldOrigin = .ai,
        userEdited: Bool = false,
        selected: Bool = true,
        barcode: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.storage = storage
        self.shelfLifeDays = shelfLifeDays
        self.action = action
        self.mergeTargetId = mergeTargetId
        self.mergeTargetLabel = mergeTargetLabel
        self.origin = origin
        self.userEdited = userEdited
        self.selected = selected
        self.barcode = barcode
        self.tags = tags
    }

    /// `origin` and `id` are preserved (never overridden).
    func copyWith(
        name: String? = nil,
        quantity: String? = nil,
        unit: String? = nil,
        category: String? = nil,
        storage: IconType? = nil,
        shelfLifeDays: Int? = nil,
        action: IntakeAction? = nil,
        mergeTargetId: String? = nil,
        mergeTargetLabel: String? = nil,
        selected: Bool? = nil,
        userEdited: Bool? = nil,
        clearShelfLifeDays: Bool = false
    ) -> IntakeProposal {
        IntakeProposal(
            id: id,
            name: name ?? self.name,
            quantity: quantity ?? self.quantity,
            unit: unit ?? self.unit,
            category: category ?? self.category,
            storage: storage ?? self.storage,
            // `?? self` can't clear a set value; `clearShelfLifeDays` forces nil so
            // the 保质期 chip's 「未设置」arm actually resets (was a silent no-op).
            shelfLifeDays: clearShelfLifeDays ? nil : (shelfLifeDays ?? self.shelfLifeDays),
            action: action ?? self.action,
            mergeTargetId: mergeTargetId ?? self.mergeTargetId,
            mergeTargetLabel: mergeTargetLabel ?? self.mergeTargetLabel,
            origin: origin,
            userEdited: userEdited ?? self.userEdited,
            selected: selected ?? self.selected,
            barcode: barcode,
            tags: tags
        )
    }
}

/// One candidate inventory row a deduction could land on.
///
/// `inventoryRowIndex` is a POSITIONAL key at compute time, NOT apply-time
/// truth. `inventoryRowId` (when non-empty) / name+unit are the stable identity
/// callers re-resolve against the live inventory before applying.
struct DeductionCandidate: Equatable, Sendable {
    var inventoryRowIndex: Int
    var displayLabel: String
    var inventoryRowId: String
    var inventoryRowName: String
    var inventoryRowUnit: String

    init(
        inventoryRowIndex: Int,
        displayLabel: String,
        inventoryRowId: String = "",
        inventoryRowName: String = "",
        inventoryRowUnit: String = ""
    ) {
        self.inventoryRowIndex = inventoryRowIndex
        self.displayLabel = displayLabel
        self.inventoryRowId = inventoryRowId
        self.inventoryRowName = inventoryRowName
        self.inventoryRowUnit = inventoryRowUnit
    }
}

/// Deduction proposal (one recipe ingredient to deduct from inventory).
struct DeductionProposal {
    var id: String
    var recipeIngredientName: String
    var requiredQty: String
    var candidates: [DeductionCandidate]
    /// Chosen inventory row index. -1 when `action == .skip`.
    var chosenIndex: Int
    /// Quantity to deduct, as a string (matches `Ingredient.quantity` shape).
    var deductAmount: String
    var action: DeductionAction
    var selected: Bool

    init(
        id: String,
        recipeIngredientName: String,
        requiredQty: String,
        candidates: [DeductionCandidate],
        chosenIndex: Int,
        deductAmount: String,
        action: DeductionAction = .deduct,
        selected: Bool = true
    ) {
        self.id = id
        self.recipeIngredientName = recipeIngredientName
        self.requiredQty = requiredQty
        self.candidates = candidates
        self.chosenIndex = chosenIndex
        self.deductAmount = deductAmount
        self.action = action
        self.selected = selected
    }

    /// Skip placeholder: no candidates, chosenIndex -1, deductAmount "0".
    static func empty(
        id: String,
        recipeIngredientName: String,
        requiredQty: String
    ) -> DeductionProposal {
        DeductionProposal(
            id: id,
            recipeIngredientName: recipeIngredientName,
            requiredQty: requiredQty,
            candidates: [],
            chosenIndex: -1,
            deductAmount: "0",
            action: .skip,
            selected: false
        )
    }

    func copyWith(
        chosenIndex: Int? = nil,
        deductAmount: String? = nil,
        action: DeductionAction? = nil,
        selected: Bool? = nil
    ) -> DeductionProposal {
        DeductionProposal(
            id: id,
            recipeIngredientName: recipeIngredientName,
            requiredQty: requiredQty,
            candidates: candidates,
            chosenIndex: chosenIndex ?? self.chosenIndex,
            deductAmount: deductAmount ?? self.deductAmount,
            action: action ?? self.action,
            selected: selected ?? self.selected
        )
    }
}
