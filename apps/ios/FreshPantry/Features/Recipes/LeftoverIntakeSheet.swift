import SwiftUI

/// Post-cook leftover intake sheet (剩菜入库): a minimal prefilled form — dish
/// name, 份数, fridge shelf-life days — that saves ONE new inventory row
/// through the canonical `IntakeController` path (persist + outbox enqueue +
/// frequency memory), the same seam the manual add form uses. A persist
/// failure surfaces inline and keeps the sheet open (mirrors
/// `ShoppingAddSheet.addError`) — never a silent fake success.
struct LeftoverIntakeSheet: View {
    let recipe: Recipe
    /// Called with the saved dish name after a successful persist, so the
    /// presenter can toast.
    var onSaved: (String) -> Void

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var draft: LeftoverDraft
    @State private var isSaving = false
    /// Inline persist-failure notice — the sheet never closes as if it saved.
    @State private var saveError: String?

    init(recipe: Recipe, onSaved: @escaping (String) -> Void = { _ in }) {
        self.recipe = recipe
        self.onSaved = onSaved
        _draft = State(initialValue: LeftoverDraft.from(recipe: recipe))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("剩菜") {
                    TextField("名称（必填）", text: $draft.name)
                        .onChange(of: draft.name) { _, _ in saveError = nil }
                    Stepper(value: $draft.servings, in: 1...99) {
                        labeledValue("份数", "\(draft.servings) 份")
                    }
                }
                Section {
                    Stepper(value: $draft.days, in: 1...14) {
                        labeledValue("保质期", "\(draft.days) 天")
                    }
                } header: {
                    Text("冷藏保质期")
                } footer: {
                    Text("将存入冷藏，分类「其他」。熟食冷藏建议 3 天内吃完。")
                }
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.circle")
                            .font(.fkBodySmall)
                            .foregroundStyle(Color.fkDanger)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.fkSurface)
            .navigationTitle("存为剩菜")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") { Task { await save() } }
                        .font(.fkLabelLarge)
                        .disabled(!draft.canSave || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.fkOnSurface)
            Spacer(minLength: FkSpacing.sm)
            Text(value)
                .foregroundStyle(Color.fkOnSurfaceVariant)
        }
        .font(.fkBodyMedium)
    }

    /// Persists the leftover as one new inventory row via `IntakeController`
    /// (the outbox-capable add path). Dismisses only on a confirmed persist;
    /// a failure stays open with an inline notice.
    private func save() async {
        guard draft.canSave, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let controller = IntakeController(
            repository: dependencies.inventoryRepository,
            householdID: dependencies.householdID,
            syncWriter: dependencies.syncWriter,
            isPro: { dependencies.proStore.isPro }
        )
        let outcome = await controller.apply([draft.proposal()])
        if outcome.limitReached {
            saveError = "免费版最多记录 \(FreeTier.inventoryLimit) 条库存"
        } else if outcome.persisted {
            onSaved(draft.name.trimmed)
            dismiss()
        } else {
            saveError = "保存失败，请重试。"
        }
    }
}
