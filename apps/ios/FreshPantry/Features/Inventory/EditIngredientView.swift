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
            .navigationTitle("编辑食材")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "保存中…" : "保存") { Task { await submit() } }
                        .font(.fkLabelLarge)
                        .disabled(!form.canSubmit || isSaving)
                }
            }
            .sheet(isPresented: $showUnitPicker) {
                FkPickerSheet(
                    title: "选择单位",
                    options: form.unitOptions.map { FkPickerOption(value: $0, label: $0) },
                    selected: form.unit
                ) { form.setUnit($0) }
            }
            .sheet(isPresented: $showCategoryPicker) {
                FkPickerSheet(
                    title: "选择分类",
                    options: FoodCategories.values.map { FkPickerOption(value: $0, label: $0) },
                    selected: FoodCategories.dropdownValue(form.category)
                ) { form.setCategory($0) }
            }
            .sheet(isPresented: $showStoragePicker) {
                FkPickerSheet(
                    title: "存放位置",
                    options: IconType.allCases.map { FkPickerOption(value: $0, label: $0.storageAreaLabel) },
                    selected: form.storage
                ) { form.setStorage($0) }
            }
        }
    }

    // MARK: Fields

    private var nameField: some View {
        FkFormField(label: "名称") {
            FkTextFieldPill(
                text: $form.name,
                placeholder: "如:牛奶、鸡蛋",
                submitLabel: .next
            )
            .focused($nameFocused)
        }
    }

    private var quantityRow: some View {
        HStack(alignment: .bottom, spacing: FkSpacing.md) {
            FkFormField(label: "数量") {
                FkTextFieldPill(
                    text: $form.quantity,
                    placeholder: "1",
                    keyboard: .decimalPad
                )
            }
            FkFormField(label: "单位") {
                FkValuePill(value: form.unit) { showUnitPicker = true }
            }
            .frame(maxWidth: 140)
        }
    }

    private var categoryField: some View {
        FkFormField(label: "分类") {
            FkValuePill(value: FoodCategories.dropdownValue(form.category)) {
                showCategoryPicker = true
            }
        }
    }

    private var storageField: some View {
        FkFormField(label: "存放位置") {
            FkValuePill(value: form.storage.storageAreaLabel, systemImage: storageIcon) {
                showStoragePicker = true
            }
        }
    }

    private var shelfLifeField: some View {
        FkFormField(label: "保质期") {
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FkSpacing.sm) {
                        ForEach(form.shelfLifePresets, id: \.self) { days in
                            FkChip(
                                label: "\(days)天",
                                isSelected: customShelfLife.isEmpty && form.shelfLifeDays == days
                            ) {
                                customShelfLife = ""
                                form.setShelfLife(days)
                            }
                        }
                        FkChip(
                            label: "不过期",
                            isSelected: form.shelfLifeDays == nil && customShelfLife.isEmpty
                        ) {
                            customShelfLife = ""
                            form.setShelfLife(nil)
                        }
                    }
                }
                HStack(spacing: FkSpacing.sm) {
                    Text("自定义")
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                    TextField("天数", text: $customShelfLife)
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
                    Text("天")
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
        }
    }

    private var tagsField: some View {
        FkFormField(label: "标签") {
            IngredientTagsEditor(tags: $form.tags)
        }
    }

    private var storageIcon: String {
        switch form.storage {
        case .fridge: return "refrigerator"
        case .freezer: return "snowflake"
        case .pantry: return "cabinet"
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
            submitError = "保存失败，请重试"
        }
    }
}
