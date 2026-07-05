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
                Section(String(localized: "recipe.leftover.section")) {
                    TextField(String(localized: "recipe.leftover.namePlaceholder"), text: $draft.name)
                        .onChange(of: draft.name) { _, _ in saveError = nil }
                    Stepper(value: $draft.servings, in: 1...99) {
                        labeledValue(String(localized: "recipe.leftover.servings"), String(localized: "recipe.leftover.servingsValue \(draft.servings)"))
                    }
                }
                Section {
                    Stepper(value: $draft.days, in: 1...14) {
                        labeledValue(String(localized: "recipe.leftover.shelfLife"), String(localized: "recipe.leftover.daysValue \(draft.days)"))
                    }
                } header: {
                    Text(String(localized: "recipe.leftover.fridgeShelfLife"))
                } footer: {
                    Text(String(localized: "recipe.leftover.fridgeFooter"))
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
            .navigationTitle(String(localized: "recipe.leftover.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "recipe.leftover.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? String(localized: "recipe.leftover.saving") : String(localized: "recipe.leftover.save")) { Task { await save() } }
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
            saveError = String(localized: "recipe.leftover.freeTierLimit \(FreeTier.inventoryLimit)")
        } else if outcome.persisted {
            onSaved(draft.name.trimmed)
            dismiss()
        } else {
            saveError = String(localized: "recipe.leftover.saveFailed")
        }
    }
}
