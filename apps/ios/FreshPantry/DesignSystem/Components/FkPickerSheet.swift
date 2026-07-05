import SwiftUI

/// One option in an `FkPickerSheet`.
struct FkPickerOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var subtitle: String?

    var id: Value { value }

    init(value: Value, label: String, subtitle: String? = nil) {
        self.value = value
        self.label = label
        self.subtitle = subtitle
    }
}

/// Modal single-select picker used for unit / category / storage choices.
/// Ported from Flutter `PickerSheet<T>`: a titled list of options with a
/// trailing check on the current selection; tapping an option commits + dismisses.
struct FkPickerSheet<Value: Hashable>: View {
    let title: String
    let options: [FkPickerOption<Value>]
    let selected: Value
    let onSelect: (Value) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        Button {
                            onSelect(option.value)
                            dismiss()
                        } label: {
                            row(option)
                        }
                        .buttonStyle(.fkPressable)
                        if index < options.count - 1 {
                            Rectangle().fill(Color.fkHair).frame(height: 0.5)
                                .padding(.leading, FkSpacing.lg)
                        }
                    }
                }
                .padding(.vertical, FkSpacing.xs)
            }
            .background(Color.fkSurface)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "component.action.done")) { dismiss() }
                        .font(.fkLabelLarge)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ option: FkPickerOption<Value>) -> some View {
        HStack(spacing: FkSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                    .font(.fkTitleMedium)
                    .foregroundStyle(Color.fkOnSurface)
                if let subtitle = option.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.fkBodySmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
            Spacer(minLength: FkSpacing.sm)
            if option.value == selected {
                Image(systemName: "checkmark")
                    .font(.system(size: FkSize.iconSm, weight: .bold))
                    .foregroundStyle(Color.fkPrimary)
            }
        }
        .padding(.vertical, FkSpacing.md)
        .padding(.horizontal, FkSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // The checkmark conveys selection only visually; expose it to VoiceOver
        // so users know which option is already active.
        .accessibilityAddTraits(option.value == selected ? .isSelected : [])
    }
}
