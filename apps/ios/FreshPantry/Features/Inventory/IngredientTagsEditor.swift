import SwiftUI

/// Inventory tag (标签) editor: a wrap of deletable chips plus an add field, bound
/// to a `[String]` tag list. Used by both the add and edit ingredient forms.
///
/// Mirrors `DietaryExclusionEditor`'s shape (FlowLayout + add-on-submit + inline
/// delete), but tags preserve their display casing — so it canonicalizes through
/// `Ingredient.normalizeTags` (trim / drop empty / case-insensitive de-dupe,
/// first-casing wins) rather than lowercasing. The binding holds the canonical
/// list at all times; the parent form re-normalizes on save defensively.
struct IngredientTagsEditor: View {
    @Binding var tags: [String]

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: FkSpacing.md) {
            if !tags.isEmpty {
                FlowLayout(spacing: FkSpacing.sm) {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(label: tag) { remove(tag) }
                    }
                }
            }

            HStack(spacing: FkSpacing.sm) {
                TextField(String(localized: "inventory.tags.addPlaceholder"), text: $draft)
                    .font(.fkBodyMedium)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($fieldFocused)
                    .onSubmit(commit)
                Button(action: commit) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: FkSize.iconMd))
                        .foregroundStyle(canAdd ? Color.fkPrimary : Color.fkOutline)
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
                .accessibilityLabel(String(localized: "inventory.tags.add"))
            }
        }
        .padding(.vertical, FkSpacing.xs)
    }

    private var canAdd: Bool { !draft.trimmed.isEmpty }

    /// Appends the draft (canonicalizing the whole list so a duplicate / blank is
    /// a no-op) and clears the field, keeping focus for rapid entry.
    private func commit() {
        guard canAdd else { return }
        tags = Ingredient.normalizeTags(tags + [draft])
        draft = ""
        fieldFocused = true
    }

    private func remove(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}

/// A tag chip with an inline delete affordance. Self-contained (the Settings
/// `DeletableChip` is private) but visually identical.
private struct TagChip: View {
    let label: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: FkSpacing.xs) {
            Text(label)
                .font(.fkLabelMedium)
                .foregroundStyle(Color.fkOnSurface)
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.fkOutline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "inventory.tags.remove \(label)"))
        }
        .padding(.leading, FkSpacing.md)
        .padding(.trailing, FkSpacing.sm)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.fkSurfaceContainer)
                .overlay(Capsule().strokeBorder(Color.fkHair, lineWidth: 1))
        )
    }
}
