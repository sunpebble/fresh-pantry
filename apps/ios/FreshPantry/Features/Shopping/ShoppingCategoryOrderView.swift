import SwiftUI

/// Drag-to-reorder the shopping list's category sections to match a user's own
/// supermarket aisle route (#19). Persists device-locally via
/// `ShoppingCategoryOrder`; `onSaved` lets the caller reload so the new order
/// takes effect immediately.
struct ShoppingCategoryOrderView: View {
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var order: [String] = ShoppingCategoryOrder.load()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order, id: \.self) { category in
                        HStack(spacing: FkSpacing.md) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(Color.fkOnSurfaceVariant)
                            Text(FoodCategories.displayLabel(for: category))
                                .font(.fkBodyLarge)
                                .foregroundStyle(Color.fkOnSurface)
                        }
                    }
                    .onMove { source, destination in
                        order.move(fromOffsets: source, toOffset: destination)
                    }
                } footer: {
                    Text(String(localized: "shopping.categoryOrder.hint"))
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(String(localized: "shopping.categoryOrder.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "shopping.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "shopping.done")) {
                        ShoppingCategoryOrder.save(order)
                        onSaved()
                        dismiss()
                    }
                }
            }
        }
    }
}
