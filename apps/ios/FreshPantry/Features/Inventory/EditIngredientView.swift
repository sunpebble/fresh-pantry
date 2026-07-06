import SwiftUI

/// Edit an existing inventory row — name / quantity+unit / category / storage /
/// shelf-life. Presented as a sheet from the detail screen's pencil. On save it
/// applies a direct positional update through `InventoryStore.update` (NOT the
/// intake/merge pipeline — an edit never merges into another batch), then calls
/// `onSaved` and dismisses. Mirrors the Flutter add-ingredient screen's edit mode.
struct EditIngredientView: View {
    let store: InventoryStore
    /// Called after a successful save (the caller pops the detail back to the list).
    var onSaved: () -> Void = {}

    @State private var form: EditIngredientForm
    @State private var isSaving = false
    @State private var submitError: String?
    @State private var showUnitPicker = false
    @State private var showCategoryPicker = false
    @State private var showStoragePicker = false
    @State private var customShelfLife: String
    @FocusState private var nameFocused: Bool

    @Environment(\.dismiss) private var dismiss

    init(original: Ingredient, store: InventoryStore, onSaved: @escaping () -> Void = {}) {
        self.store = store
        self.onSaved = onSaved
        _form = State(initialValue: EditIngredientForm(original))
        // Prefill the custom-days field when the row's shelf-life isn't a preset
        // (so a non-standard value is visible + selected rather than orphaned).
        let seeded = original.shelfLifeDays
        if let seeded, seeded > 0, !FoodKnowledge.shelfLifePresets.contains(seeded) {
            _customShelfLife = State(initialValue: String(seeded))
        } else {
            _customShelfLife = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FkSpacing.lg) {
                    if let submitError {
                        FkSubmitErrorNotice(message: submitError)
                    }
                    nameField
                    quantityRow
                    categoryField
                    storageField
                    shelfLifeField
                    tagsField
                }
                .padding(FkSpacing.lg)
            }
            .background(Color.fkSurface)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(String(localized: "inventory.editIngredient.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "inventory.action.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? String(localized: "inventory.editIngredient.saving") : String(localized: "inventory.editIngredient.save")) { Task { await submit() } }
                        .font(.fkLabelLarge)
                        .disabled(!form.canSubmit || isSaving)
                }
            }
            .sheet(isPresented: $showUnitPicker) {
                FkPickerSheet(
                    title: String(localized: "inventory.picker.unit"),
                    options: form.unitOptions.map { FkPickerOption(value: $0, label: UnitLabels.displayLabel(for: $0)) },
                    selected: form.unit
                ) { form.setUnit($0) }
            }
            .sheet(isPresented: $showCategoryPicker) {
                FkPickerSheet(
                    title: String(localized: "inventory.picker.category"),
                    options: FoodCategories.values.map { FkPickerOption(value: $0, label: FoodCategories.displayLabel(for: $0)) },
                    selected: FoodCategories.dropdownValue(form.category)
                ) { form.setCategory($0) }
            }
            .sheet(isPresented: $showStoragePicker) {
                FkPickerSheet(
                    title: String(localized: "inventory.picker.storage"),
                    options: IconType.allCases.map { FkPickerOption(value: $0, label: $0.storageAreaLabel) },
                    selected: form.storage
                ) { form.setStorage($0) }
            }
        }
    }

    // MARK: Fields

    private var nameField: some View {
        FkFormField(label: String(localized: "inventory.field.name")) {
            FkTextFieldPill(
                text: $form.name,
                placeholder: String(localized: "inventory.field.namePlaceholder"),
                submitLabel: .next
            )
            .focused($nameFocused)
        }
    }

    private var quantityRow: some View {
        HStack(alignment: .bottom, spacing: FkSpacing.md) {
            FkFormField(label: String(localized: "inventory.field.quantity")) {
                FkTextFieldPill(
                    text: $form.quantity,
                    placeholder: "1",
                    keyboard: .decimalPad
                )
            }
            FkFormField(label: String(localized: "inventory.field.unit")) {
                FkValuePill(value: UnitLabels.displayLabel(for: form.unit)) { showUnitPicker = true }
            }
            .frame(maxWidth: 140)
        }
    }

    private var categoryField: some View {
        FkFormField(label: String(localized: "inventory.field.category")) {
            FkValuePill(value: FoodCategories.displayLabel(for: FoodCategories.dropdownValue(form.category))) {
                showCategoryPicker = true
            }
        }
    }

    private var storageField: some View {
        FkFormField(label: String(localized: "inventory.field.storage")) {
            FkValuePill(value: form.storage.storageAreaLabel, systemImage: form.storage.sfSymbolOutline) {
                showStoragePicker = true
            }
        }
    }

    private var shelfLifeField: some View {
        FkFormField(label: String(localized: "inventory.field.shelfLife")) {
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FkSpacing.sm) {
                        ForEach(form.shelfLifePresets, id: \.self) { days in
                            FkChip(
                                label: String(localized: "inventory.shelfLife.days \(days)"),
                                isSelected: customShelfLife.isEmpty && form.shelfLifeDays == days
                            ) {
                                customShelfLife = ""
                                form.setShelfLife(days)
                            }
                        }
                        FkChip(
                            label: String(localized: "inventory.shelfLife.never"),
                            isSelected: form.shelfLifeDays == nil && customShelfLife.isEmpty
                        ) {
                            customShelfLife = ""
                            form.setShelfLife(nil)
                        }
                    }
                }
                HStack(spacing: FkSpacing.sm) {
                    Text(String(localized: "inventory.shelfLife.custom"))
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                    TextField(String(localized: "inventory.shelfLife.dayCount"), text: $customShelfLife)
                        .font(.fkTitleMedium)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 80)
                        .padding(.horizontal, FkSpacing.sm)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: FkRadius.sm, style: .continuous)
                                .fill(Color.fkSurfaceContainer)
                        )
                        .onChange(of: customShelfLife) { _, value in
                            if let days = Int(value.trimmed), days > 0 {
                                form.setShelfLife(days)
                            }
                        }
                    Text(String(localized: "inventory.shelfLife.unitDay"))
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
        }
    }

    private var tagsField: some View {
        FkFormField(label: String(localized: "inventory.field.tags")) {
            IngredientTagsEditor(tags: $form.tags)
        }
    }

    // MARK: Submit

    private func submit() async {
        guard form.canSubmit, !isSaving else { return }
        submitError = nil
        nameFocused = false
        isSaving = true
        defer { isSaving = false }

        let edited = form.buildEdited()
        let saved = await store.update(form.original, to: edited)
        if saved {
            onSaved()
            dismiss()
        } else {
            submitError = String(localized: "inventory.editIngredient.saveFailed")
        }
    }
}
