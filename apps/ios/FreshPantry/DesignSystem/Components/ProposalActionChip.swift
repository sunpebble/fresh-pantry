import SwiftUI

/// Pill chip showing (and toggling) an intake proposal's action: start a new
/// batch vs merge into an existing inventory row. Ported from Flutter
/// `ProposalActionChip.intake`.
///
/// `newRow` reads as a soft-primary "新建 Batch"; `mergeInto` reads as a warm
/// "合并 → <target>". Disabled (no toggle) when there is no merge target to
/// switch to, or when the rules lock the action (a perishable can only be a new
/// batch).
struct ProposalActionChip: View {
    let action: IntakeAction
    var mergeTargetLabel: String?
    var locked: Bool = false
    let onToggle: () -> Void

    var body: some View {
        Button(action: { if !locked { onToggle() } }) {
            HStack(spacing: FkSpacing.xs) {
                Text(label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !locked {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .font(.fkLabelMedium)
            .foregroundStyle(foreground)
            .padding(.horizontal, FkSpacing.md)
            .padding(.vertical, 6)
            .background(Capsule().fill(background))
        }
        .buttonStyle(.fkPressable)
        .disabled(locked)
    }

    private var label: String {
        switch action {
        case .newRow:
            return String(localized: "component.intakeAction.newBatch")
        case .mergeInto:
            guard let mergeTargetLabel, !mergeTargetLabel.isEmpty else { return String(localized: "component.intakeAction.merge") }
            return String(localized: "component.intakeAction.mergeInto \(mergeTargetLabel)")
        }
    }

    private var background: Color {
        action == .newRow ? .fkPrimarySoft : .fkWarnSoft
    }

    private var foreground: Color {
        action == .newRow ? .fkPrimaryContainer : .fkWarnInk
    }
}
