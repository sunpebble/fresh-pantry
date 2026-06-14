import SwiftUI

/// Inline search field ported from Flutter `_SearchField`: a rounded container
/// surface with a leading glass icon, a borderless text field, and a clear
/// button when non-empty.
struct FkSearchField: View {
    @Binding var text: String
    var placeholder: String = "搜索食材"

    var body: some View {
        HStack(spacing: FkSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: FkSize.iconSm, weight: .semibold))
                .foregroundStyle(Color.fkOnSurfaceVariant)
            TextField(placeholder, text: $text)
                .font(.fkBodyMedium)
                .foregroundStyle(Color.fkOnSurface)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: FkSize.iconSm))
                        .foregroundStyle(Color.fkOutline)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.horizontal, FkSpacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.chip, style: .continuous)
                .fill(Color.fkSurfaceContainer)
        )
    }
}
