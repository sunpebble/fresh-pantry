import SwiftUI

/// Minus / value / plus stepper over a string-typed number, with an optional
/// suffix. Ported from Flutter `InlineNumberStepper`.
///
/// The value stays a string (matching `Ingredient.quantity` shape); a
/// non-numeric value disables both buttons rather than coercing. Each bump
/// clamps to `[min, max]` and re-formats via `QuantityText.formatQuantity` so no
/// float artifacts leak in.
struct FkInlineStepper: View {
    let value: String
    var min: Double = 0
    var max: Double = 9999
    var suffix: String?
    /// Tap handler for the value label (tap-to-edit); nil keeps it inert. The
    /// only way to FIX a non-numeric value (both step buttons are disabled).
    var onTapValue: (() -> Void)?
    let onChanged: (String) -> Void

    private var parsed: Double? { QuantityText.numeric(value) }

    var body: some View {
        HStack(spacing: FkSpacing.sm) {
            stepButton(systemImage: "minus", enabled: canDecrement) { bump(by: -1) }

            if let onTapValue {
                Button(action: onTapValue) { valueLabel }
                    .buttonStyle(.fkPressable)
            } else {
                valueLabel
            }

            stepButton(systemImage: "plus", enabled: canIncrement) { bump(by: 1) }
        }
    }

    private var valueLabel: some View {
        HStack(spacing: 2) {
            Text(value)
                .font(.fkTitleSmall)
                .foregroundStyle(Color.fkOnSurface)
                .monospacedDigit()
            if let suffix {
                Text(suffix)
                    .font(.fkLabelSmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
        .frame(minWidth: 34)
    }

    private var canDecrement: Bool {
        guard let parsed else { return false }
        return parsed > min
    }

    private var canIncrement: Bool {
        guard let parsed else { return false }
        return parsed < max
    }

    private func bump(by delta: Double) {
        guard let parsed else { return }
        let next = Swift.min(Swift.max(parsed + delta, min), max)
        onChanged(QuantityText.formatQuantity(next))
    }

    private func stepButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        let suffixLabel = suffix.map { " \($0)" } ?? ""
        let label = systemImage == "minus"
            ? String(localized: "component.stepper.decrease \(suffixLabel)")
            : String(localized: "component.stepper.increase \(suffixLabel)")
        return Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? Color.fkPrimary : Color.fkOutlineVariant)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(enabled ? Color.fkPrimarySoft : Color.fkSurfaceContainer)
                )
        }
        .buttonStyle(.fkPressable)
        .disabled(!enabled)
        // Icon-only buttons announce just "minus"/"plus" without context; give
        // VoiceOver the action + the unit being adjusted.
        .accessibilityLabel(label)
    }
}
