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
                Label("本周存为模板", systemImage: "square.and.arrow.down")
            }
            .disabled(store.entriesInVisibleWeek.allSatisfy { $0.recipeId.isEmpty })

            Button {
                showApplySheet = true
            } label: {
                Label("应用模板", systemImage: "square.and.arrow.up")
            }
            .disabled(store.templates().isEmpty)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .accessibilityLabel("膳食模板")
        .alert("存为模板", isPresented: $showSavePrompt) {
            TextField("模板名称(如:工作日)", text: $templateName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                if store.saveCurrentWeekAsTemplate(name: templateName) != nil {
                    savedToast = "已存为模板"
                }
            }
        } message: {
            Text("把本周的菜谱保存成可复用的模板")
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
                    Text("还没有保存的模板")
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
                                    Text("\(template.items.count) 道菜")
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
            .navigationTitle("应用模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { templates = store.templates() }
        }
    }
}
