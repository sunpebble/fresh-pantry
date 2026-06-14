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
                            Text(category)
                                .font(.fkBodyLarge)
                                .foregroundStyle(Color.fkOnSurface)
                        }
                    }
                    .onMove { source, destination in
                        order.move(fromOffsets: source, toOffset: destination)
                    }
                } footer: {
                    Text("拖动调整顺序,购物清单将按此顺序分组——对齐你常逛超市的货架动线。")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("分类排序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        ShoppingCategoryOrder.save(order)
                        onSaved()
                        dismiss()
                    }
                }
            }
        }
    }
}
