import SwiftUI

/// Horizontal recipe list card: a category-tinted cover (remote image when the
/// recipe has one, else a category glyph), the recipe name, a category chip, a
/// meta row (difficulty label · N 分钟), and a favorite heart overlay on the
/// cover. Ported from the Flutter `RecipeCard` (browse scope only — no
/// ingredient-match progress bar or expiring badge in this phase).
struct RecipeCard: View {
    let recipe: Recipe
    let isFavorite: Bool
    /// Tapping the heart toggles favorite without triggering the card's own tap.
    let onToggleFavorite: () -> Void
    /// Optional ingredient-match progress (in-stock count / total). When both are
    /// supplied a progress bar + "缺 N 件" line renders; nil keeps the browse-only
    /// card (the meal-plan picker passes nil).
    var matchedCount: Int? = nil
    var totalIngredients: Int? = nil
    /// Distinct expiring/expired items this recipe would use up; a "临期 · N" badge
    /// renders when > 0.
    var expiringUse: Int = 0

    private var palette: FkCategoryColors { FkCategoryIcon.palette(for: recipe.category) }

    var body: some View {
        FkCard(padding: 0) {
            HStack(spacing: FkSpacing.md) {
                cover
                content
                    .padding(.vertical, FkSpacing.md)
                    .padding(.trailing, FkSpacing.md)
            }
        }
    }

    // MARK: Cover

    private var cover: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                .fill(palette.tint)
                .frame(width: coverSize, height: coverSize)
                .overlay { coverImage }
                .clipShape(RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous))

            favoriteHeart
                .padding(FkSpacing.xs)
        }
    }

    private var coverImage: some View {
        RecipeImage(source: recipe.imageUrl) { fallbackGlyph }
    }

    private var fallbackGlyph: some View {
        Image(systemName: FkCategoryIcon.symbol(for: recipe.category))
            .font(.system(size: coverSize * 0.42, weight: .semibold))
            .foregroundStyle(palette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var favoriteHeart: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: FkSize.iconSm, weight: .semibold))
                .foregroundStyle(isFavorite ? Color.fkDanger : Color.fkOnPrimary)
                .padding(6)
                .background(Circle().fill(Color.fkOnImageScrim))
        }
        .buttonStyle(.plain)
        // Wins the gesture so the card's own tap doesn't fire (parity with the
        // Flutter inner GestureDetector).
        .accessibilityLabel(isFavorite ? "取消收藏" : "收藏")
    }

    // MARK: Content

    private var content: some View {
        VStack(alignment: .leading, spacing: FkSpacing.xs) {
            Text(recipe.name)
                .font(.fkTitleMedium)
                .foregroundStyle(Color.fkOnSurface)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if !recipe.category.trimmed.isEmpty {
                Text(recipe.category)
                    .font(.fkLabelSmall)
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, FkSpacing.sm)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(palette.tint))
            }

            HStack(spacing: FkSpacing.md) {
                metaItem(systemImage: "flame", text: recipe.difficultyLabel)
                metaItem(systemImage: "clock", text: "\(recipe.cookingMinutes) 分钟")
                if expiringUse > 0 {
                    Text("临期 · \(expiringUse)")
                        .font(.fkLabelSmall)
                        .foregroundStyle(Color.fkDanger)
                        .padding(.horizontal, FkSpacing.sm)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.fkWarnSoft))
                }
            }

            matchProgress
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Ingredient-match progress bar + "已有 m/total · 缺 k 件" line. Renders only
    /// when both match counts are supplied and the recipe has ingredients.
    @ViewBuilder
    private var matchProgress: some View {
        if let matched = matchedCount, let total = totalIngredients, total > 0 {
            let fraction = Double(matched) / Double(total)
            let missing = max(total - matched, 0)
            VStack(alignment: .leading, spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.fkSurfaceContainer)
                        Capsule().fill(missing == 0 ? Color.fkSuccess : Color.fkPrimary)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 4)
                Text(missing == 0 ? "食材齐全" : "已有 \(matched)/\(total) · 缺 \(missing) 件")
                    .font(.fkLabelSmall)
                    .foregroundStyle(missing == 0 ? Color.fkSuccess : Color.fkOnSurfaceVariant)
            }
            .padding(.top, 2)
        }
    }

    private func metaItem(systemImage: String, text: String) -> some View {
        HStack(spacing: FkSpacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.fkLabelSmall)
        }
        .foregroundStyle(Color.fkOnSurfaceVariant)
    }

    private let coverSize: CGFloat = 96
}
