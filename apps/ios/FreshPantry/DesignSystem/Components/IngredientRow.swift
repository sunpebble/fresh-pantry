import SwiftUI

/// One inventory list row: category avatar, name, quantity·unit, a storage chip,
/// the urgency badge, and the localized expiry label. Read-only; the parent
/// supplies the tap target via `NavigationLink` / `Button`.
struct IngredientRow: View {
    let ingredient: Ingredient

    var body: some View {
        HStack(spacing: FkSpacing.md) {
            FkCategoryAvatar(
                imageUrl: ingredient.imageUrl,
                category: ingredient.category,
                size: 48
            )

            VStack(alignment: .leading, spacing: FkSpacing.xs) {
                Text(ingredient.displayName)
                    .font(.fkTitleMedium)
                    .foregroundStyle(ingredient.state == .expired ? Color.fkOnSurfaceVariant : Color.fkOnSurface)
                    .lineLimit(1)

                HStack(spacing: FkSpacing.sm) {
                    Text("\(ingredient.quantity)\(UnitLabels.displayLabel(for: ingredient.unit))")
                        .font(.fkBodySmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                    storageChip
                }
            }

            Spacer(minLength: FkSpacing.sm)

            VStack(alignment: .trailing, spacing: FkSpacing.xs) {
                UrgencyBadge(state: ingredient.state)
                if let label = ingredient.expiryLabel, !label.isEmpty {
                    Text(label)
                        .font(.fkLabelSmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
        }
        .padding(.vertical, FkSpacing.sm)
        .contentShape(Rectangle())
    }

    private var storageChip: some View {
        HStack(spacing: 3) {
            Image(systemName: ingredient.storage.sfSymbol)
                .font(.system(size: 10, weight: .semibold))
            Text(ingredient.storage.storageAreaLabel)
                .font(.fkLabelSmall)
        }
        .foregroundStyle(Color.fkOnSurfaceVariant)
        .padding(.horizontal, FkSpacing.sm)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.fkSurfaceContainer))
    }
}
