import SwiftUI

/// Cook-time Deduction Review screen: renders a `[DeductionProposal]` list the
/// user can select/deselect, re-target (pick which inventory batch to draw
/// from), adjust the deduct amount on, or toggle to 跳过, then confirms to apply
/// the SELECTED & deductible proposals atomically through `DeductionController`
/// (reducing stock + auto-logging consumed departures). The deduction mirror of
/// `IntakeReviewView`, launched from the recipe detail "做菜" CTA.
struct DeductionReviewView: View {
    let proposals: [DeductionProposal]
    var title: String = "审核扣库存"
    /// Called after a successful apply (so the presenter can refresh + dismiss).
    var onApplied: (DeductionController.ApplyOutcome) -> Void = { _ in }

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var store: DeductionReviewStore?
    @State private var isConfirming = false
    /// Inline apply-failure notice (mirrors `LeftoverIntakeSheet.saveError`) —
    /// the sheet stays open for retry, never closing as if it deducted.
    @State private var applyError: String?

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.fkSurface)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store == nil {
                store = DeductionReviewStore(
                    proposals: proposals,
                    controller: DeductionController(
                        inventoryRepository: dependencies.inventoryRepository,
                        foodLogRepository: dependencies.foodLogRepository,
                        householdID: dependencies.householdID,
                        syncWriter: dependencies.syncWriter
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func content(_ store: DeductionReviewStore) -> some View {
        VStack(spacing: 0) {
            if store.proposals.isEmpty {
                FkEmptyState(
                    systemImage: "tray",
                    title: "没有待扣减的食材",
                    message: "这道菜还没有可对照的食材清单。"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: FkSpacing.sm) {
                        if store.hasNoDeductible {
                            noDeductibleBanner
                        }
                        ForEach(Array(store.proposals.enumerated()), id: \.element.id) { index, proposal in
                            DeductionProposalRow(
                                proposal: proposal,
                                onToggleSelected: { store.toggleSelected(proposal.id) },
                                onToggleAction: { store.toggleAction(proposal.id) },
                                onChooseCandidate: { store.chooseCandidate(proposal.id, $0) },
                                onChangeAmount: { store.updateDeductAmount(proposal.id, $0) }
                            )
                            .fkEntrance(index: index)
                        }
                    }
                    .padding(FkSpacing.lg)
                }
                if let applyError {
                    applyErrorNotice(applyError)
                }
                bottomBar(store)
            }
        }
        .background(Color.fkSurface)
    }

    /// Inline persist-failure row pinned above the confirm bar.
    private func applyErrorNotice(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.fkBodySmall)
            .foregroundStyle(Color.fkDanger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FkSpacing.lg)
            .padding(.vertical, FkSpacing.sm)
            .background(Color.fkDangerSoft)
    }

    /// Shown above the rows when every recipe ingredient is 缺货 — the screen still
    /// lists them (skip-only) so the cook sees what the recipe needs.
    private var noDeductibleBanner: some View {
        FkCard(background: .fkWarnSoft) {
            HStack(spacing: FkSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.fkWarnInk)
                Text("这道菜的食材都不在库存里,没有可扣减的项。")
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkWarnInk)
                Spacer(minLength: 0)
            }
        }
    }

    private func bottomBar(_ store: DeductionReviewStore) -> some View {
        HStack(spacing: FkSpacing.md) {
            Button {
                store.toggleSelectAll()
            } label: {
                Label(
                    store.allSelected ? "取消全选" : "全选",
                    systemImage: store.allSelected ? "checklist.unchecked" : "checklist.checked"
                )
                .font(.fkLabelMedium)
                .foregroundStyle(Color.fkPrimary)
            }
            .buttonStyle(.fkPressable)
            .disabled(store.hasNoDeductible)

            Spacer()

            Button {
                Task { await confirm(store) }
            } label: {
                Text(confirmLabel(store))
                    .font(.fkLabelLarge)
                    .foregroundStyle(Color.fkOnPrimary)
                    .padding(.horizontal, FkSpacing.xl)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(store.canConfirm ? Color.fkPrimary : Color.fkOutlineVariant)
                    )
            }
            .buttonStyle(.fkPressable)
            .disabled(!store.canConfirm || isConfirming)
        }
        .padding(.horizontal, FkSpacing.lg)
        .padding(.vertical, FkSpacing.md)
        .background(.ultraThinMaterial)
    }

    private func confirmLabel(_ store: DeductionReviewStore) -> String {
        if isConfirming { return "扣减中…" }
        return "确认扣减 (\(store.selectedCount))"
    }

    private func confirm(_ store: DeductionReviewStore) async {
        guard !isConfirming, store.canConfirm else { return }
        isConfirming = true
        defer { isConfirming = false }
        applyError = nil
        let outcome = await store.apply()
        if outcome.persisted {
            onApplied(outcome)
            dismiss()
        } else {
            // `DeductionController` contract: a failed apply mutated nothing —
            // surface it and keep the sheet open so 确认 can be retried.
            applyError = "扣减失败，请重试。"
        }
    }
}

/// Editable card for one cook-time deduction: required-ingredient name + amount,
/// select checkbox, a 扣库存/跳过 chip, a batch-source picker (when matched), the
/// deduct-amount stepper, and a 缺货 indicator when no inventory matched. Ported
/// from Flutter `DeductionProposalRow`.
private struct DeductionProposalRow: View {
    let proposal: DeductionProposal
    let onToggleSelected: () -> Void
    let onToggleAction: () -> Void
    let onChooseCandidate: (Int) -> Void
    let onChangeAmount: (String) -> Void

    @State private var showSourcePicker = false

    private var isSkip: Bool { proposal.action == .skip }
    private var hasCandidates: Bool { !proposal.candidates.isEmpty }
    private var chosen: DeductionCandidate? { ProposalApply.chosenCandidate(proposal) }

    var body: some View {
        FkCard(background: isSkip ? .fkSurfaceContainerLow : .fkSurfaceContainerLowest) {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                headerRow
                if !isSkip && hasCandidates {
                    sourceRow
                    amountRow
                } else if !hasCandidates {
                    outOfStockRow
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: FkRadius.xl, style: .continuous)
                .strokeBorder(
                    proposal.selected ? Color.fkPrimary.opacity(0.3) : Color.fkHair,
                    lineWidth: 1
                )
        )
        .sheet(isPresented: $showSourcePicker) {
            FkPickerSheet(
                title: "扣减来源批次",
                options: proposal.candidates.map {
                    FkPickerOption(value: $0.inventoryRowIndex, label: $0.displayLabel)
                },
                selected: proposal.chosenIndex
            ) { onChooseCandidate($0) }
        }
    }

    private var headerRow: some View {
        HStack(spacing: FkSpacing.sm) {
            Button(action: onToggleSelected) {
                Image(systemName: proposal.selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(proposal.selected ? Color.fkPrimary : Color.fkOutline)
            }
            .buttonStyle(.fkPressable)
            .disabled(!DeductionReviewStore.isDeductible(proposal))

            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.recipeIngredientName.isEmpty ? "(无名)" : proposal.recipeIngredientName)
                    .font(.fkTitleMedium)
                    .foregroundStyle(Color.fkOnSurface)
                    .lineLimit(1)
                if !proposal.requiredQty.trimmed.isEmpty {
                    Text("菜谱需要 \(proposal.requiredQty)")
                        .font(.fkLabelSmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }

            Spacer(minLength: FkSpacing.sm)

            DeductionActionChip(
                action: proposal.action,
                onToggle: onToggleAction
            )
        }
    }

    /// Tappable batch-source box: the chosen inventory batch + a chevron opening
    /// the candidate picker.
    private var sourceRow: some View {
        Button(action: { showSourcePicker = true }) {
            HStack(spacing: FkSpacing.sm) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                Text(chosen?.displayLabel ?? "无可用批次")
                    .font(.fkLabelMedium)
                    .foregroundStyle(Color.fkOnSurface)
                    .lineLimit(1)
                Spacer(minLength: FkSpacing.xs)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.fkOutline)
            }
            .padding(.horizontal, FkSpacing.md)
            .padding(.vertical, FkSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                    .fill(Color.fkSurfaceContainer)
            )
        }
        .buttonStyle(.fkPressable)
        .disabled(proposal.candidates.count <= 1)
    }

    private var amountRow: some View {
        HStack(spacing: FkSpacing.sm) {
            Text("扣减")
                .font(.fkLabelMedium)
                .foregroundStyle(Color.fkOnSurfaceVariant)
            FkInlineStepper(
                value: proposal.deductAmount,
                min: 1,
                suffix: chosen?.inventoryRowUnit.isEmpty == false ? chosen?.inventoryRowUnit : nil
            ) { onChangeAmount($0) }
            Spacer(minLength: 0)
        }
    }

    /// 缺货 indicator — no inventory row matched this recipe ingredient.
    private var outOfStockRow: some View {
        HStack(spacing: FkSpacing.sm) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.fkOutline)
            Text("库存中没有匹配项,这条将被跳过。")
                .font(.fkLabelMedium)
                .foregroundStyle(Color.fkOnSurfaceVariant)
            Spacer(minLength: 0)
        }
    }
}

/// Pill chip toggling a deduction proposal's action: 扣库存 vs 跳过. The deduction
/// counterpart of `ProposalActionChip` (which is intake-only). Ported from
/// Flutter `ProposalActionChip.deduction`.
private struct DeductionActionChip: View {
    let action: DeductionAction
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: FkSpacing.xs) {
                Text(action == .deduct ? "扣库存" : "跳过")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.fkLabelMedium)
            .foregroundStyle(action == .deduct ? Color.fkPrimaryContainer : Color.fkOutline)
            .padding(.horizontal, FkSpacing.md)
            .padding(.vertical, 6)
            .background(Capsule().fill(action == .deduct ? Color.fkPrimarySoft : Color.fkSurfaceContainer))
        }
        .buttonStyle(.fkPressable)
    }
}
