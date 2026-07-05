import SwiftUI

/// Toolbar menu for reusable weekly meal-plan templates (#14): save the visible
/// week as a named template, or apply a saved one onto the current week. Device
/// -local; self-contained so MealPlanView only adds one toolbar item.
struct MealPlanTemplateMenu: View {
    let store: MealPlanStore

    @State private var showSavePrompt = false
    @State private var templateName = ""
    @State private var showApplySheet = false
    @State private var savedToast: String?

    var body: some View {
        Menu {
            Button {
                templateName = ""
                showSavePrompt = true
            } label: {
                Label(String(localized: "mealPlan.template.saveThisWeek"), systemImage: "square.and.arrow.down")
            }
            .disabled(store.entriesInVisibleWeek.allSatisfy { $0.recipeId.isEmpty })

            Button {
                showApplySheet = true
            } label: {
                Label(String(localized: "mealPlan.template.apply"), systemImage: "square.and.arrow.up")
            }
            .disabled(store.templates().isEmpty)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .accessibilityLabel(String(localized: "mealPlan.template.title"))
        .alert(String(localized: "mealPlan.template.saveAs"), isPresented: $showSavePrompt) {
            TextField(String(localized: "mealPlan.template.namePlaceholder"), text: $templateName)
            Button(String(localized: "mealPlan.cancel"), role: .cancel) {}
            Button(String(localized: "mealPlan.save")) {
                if store.saveCurrentWeekAsTemplate(name: templateName) != nil {
                    savedToast = String(localized: "mealPlan.template.saved")
                }
            }
        } message: {
            Text(String(localized: "mealPlan.template.saveHint"))
        }
        .sheet(isPresented: $showApplySheet) {
            MealPlanApplyTemplateSheet(store: store)
        }
    }
}

/// Lists saved templates; tap applies to the current week, swipe deletes.
private struct MealPlanApplyTemplateSheet: View {
    let store: MealPlanStore

    @Environment(\.dismiss) private var dismiss
    @State private var templates: [MealPlanTemplate] = []

    var body: some View {
        NavigationStack {
            List {
                if templates.isEmpty {
                    Text(String(localized: "mealPlan.template.empty"))
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                } else {
                    ForEach(templates) { template in
                        Button {
                            Task {
                                _ = await store.applyTemplate(template)
                                dismiss()
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                        .font(.fkBodyLarge)
                                        .foregroundStyle(Color.fkOnSurface)
                                    Text(String(localized: "mealPlan.template.dishCount \(template.items.count)"))
                                        .font(.fkLabelSmall)
                                        .foregroundStyle(Color.fkOnSurfaceVariant)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Color.fkPrimary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { store.removeTemplate(id: templates[index].id) }
                        templates = store.templates()
                    }
                }
            }
            .navigationTitle(String(localized: "mealPlan.template.apply"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "mealPlan.done")) { dismiss() }
                }
            }
            .onAppear { templates = store.templates() }
        }
    }
}
