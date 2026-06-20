import SwiftUI

/// Shared intake-review screen: renders a `[IntakeProposal]` list the user can
/// select/deselect, edit, and re-target (新建 Batch vs 合并到 <target>), then
/// confirms to apply the SELECTED proposals atomically through
/// `IntakeController`. Built generically so it later also receives AI-parsed
/// proposals — the only entry point right now is the manual add's merge path.
struct IntakeReviewView: View {
    let proposals: [IntakeProposal]
    var title: String = "审核入库"
    /// Called after a successful apply with the outcome (so the presenter can
    /// refresh, dismiss, and — for the shopping flow — remove only the source rows
    /// whose proposal actually applied via `outcome.appliedIds`).
    var onApplied: (IntakeController.ApplyOutcome) -> Void = { _ in }

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var store: IntakeReviewStore?
    @State private var isConfirming = false

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
                store = IntakeReviewStore(
                    proposals: proposals,
                    controller: IntakeController(
                        repository: dependencies.inventoryRepository,
                        householdID: dependencies.householdID,
                        syncWriter: dependencies.syncWriter
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func content(_ store: IntakeReviewStore) -> some View {
        VStack(spacing: 0) {
            if store.proposals.isEmpty {
                FkEmptyState(
                    systemImage: "tray",
                    title: "没有待审核的项目",
                    message: "回到上一屏添加食材后再来。"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: FkSpacing.sm) {
                        ForEach(Array(store.proposals.enumerated()), id: \.element.id) { index, proposal in
                            IntakeProposalRow(
                                proposal: proposal,
                                onToggleSelected: { store.toggleSelected(proposal.id) },
                                onToggleAction: { store.toggleAction(proposal.id) },
                                onChanged: { store.updateProposal($0) }
                            )
                            .fkEntrance(index: index)
                        }
                    }
                    .padding(FkSpacing.lg)
                    .fkEntranceWindow()
                }
                if let applyError = store.applyError {
                    // 失败留在本屏可重试：库存一行没进、购物行也没被移除，
                    // 不提示的话只会看到按钮闪回原状（mirrors LeftoverIntakeSheet）。
                    Label(applyError, systemImage: "exclamationmark.circle")
                        .font(.fkBodySmall)
                        .foregroundStyle(Color.fkDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, FkSpacing.lg)
                        .padding(.vertical, FkSpacing.sm)
                }
                bottomBar(store)
            }
        }
        .background(Color.fkSurface)
    }

    private func bottomBar(_ store: IntakeReviewStore) -> some View {
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
            .disabled(store.proposals.isEmpty)

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

    private func confirmLabel(_ store: IntakeReviewStore) -> String {
        if isConfirming { return "入库中…" }
        return "入库 (\(store.selectedCount))"
    }

    private func confirm(_ store: IntakeReviewStore) async {
        guard !isConfirming, store.canConfirm else { return }
        isConfirming = true
        defer { isConfirming = false }
        let outcome = await store.apply()
        if outcome.persisted {
            onApplied(outcome)
            await dependencies.notificationCoordinator.reschedule(householdID: dependencies.householdID)
            dismiss()
        }
    }
}

/// Editable card for one intake proposal: name, select checkbox, provenance dot,
/// action chip (new batch / merge), quantity + unit + shelf-life steppers, and
/// category / storage pickers. Ported from Flutter `IntakeProposalRow`.
private struct IntakeProposalRow: View {
    let proposal: IntakeProposal
    let onToggleSelected: () -> Void
    let onToggleAction: () -> Void
    let onChanged: (IntakeProposal) -> Void

    @State private var showUnitPicker = false
    @State private var showCategoryPicker = false
    @State private var showStoragePicker = false
    /// Tap-to-edit state for the 食材名称 (the last read-only field). Seeded at
    /// edit-entry (not init) so an external store mutation never stomps a live edit.
    @State private var editingName = false
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    private let unitOptions = ["个", "只", "把", "盒", "袋", "瓶", "罐", "kg", "g", "L", "ml", "份"]

    var body: some View {
        FkCard(background: proposal.selected ? .fkSurfaceContainerLowest : .fkSurfaceContainerLow) {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                headerRow
                metaRow
                pickerRow
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: FkRadius.xl, style: .continuous)
                .strokeBorder(
                    proposal.selected ? Color.fkPrimary.opacity(0.3) : Color.fkHair,
                    lineWidth: 1
                )
        )
        .sheet(isPresented: $showUnitPicker) {
            FkPickerSheet(
                title: "选择单位",
                options: unitOptions.map { FkPickerOption(value: $0, label: $0) },
                selected: proposal.unit
            ) { onChanged(proposal.copyWith(unit: $0, userEdited: true)) }
        }
        .sheet(isPresented: $showCategoryPicker) {
            FkPickerSheet(
                title: "选择分类",
                options: FoodCategories.values.map { FkPickerOption(value: $0, label: $0) },
                selected: FoodCategories.dropdownValue(proposal.category)
            ) { onChanged(proposal.copyWith(category: $0, userEdited: true)) }
        }
        .sheet(isPresented: $showStoragePicker) {
            FkPickerSheet(
                title: "存放位置",
                options: IconType.allCases.map { FkPickerOption(value: $0, label: $0.storageAreaLabel) },
                selected: proposal.storage
            ) { onChanged(proposal.copyWith(storage: $0, userEdited: true)) }
        }
    }

    /// The 食材名称: tap to edit inline (the AI/barcode parse can mis-name an item).
    /// Commits on submit OR focus-loss (mirrors the Flutter tap-outside commit);
    /// routes through `onChanged` → store.updateProposal, which re-runs the
    /// perishable rule, so a name that turns the row perishable auto-flips
    /// merge→newRow.
    @ViewBuilder
    private var nameField: some View {
        if editingName {
            TextField("食材名称", text: $nameDraft)
                .font(.fkTitleMedium)
                .foregroundStyle(Color.fkOnSurface)
                .textFieldStyle(.plain)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { commitName() }
                .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Button {
                nameDraft = proposal.name
                editingName = true
                nameFocused = true
            } label: {
                Text(proposal.name.isEmpty ? "(无名)" : proposal.name)
                    .font(.fkTitleMedium)
                    .foregroundStyle(Color.fkOnSurface)
                    .lineLimit(1)
            }
            .buttonStyle(.fkPressable)
        }
    }

    /// Commits the edited name (trimmed) only when it changed, marking userEdited.
    /// A blank edit is discarded (a name is required) — restore the current name so
    /// a re-tap shows it, never an empty string into the store/apply pipeline.
    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameDraft = proposal.name
            editingName = false
            return
        }
        if trimmed != proposal.name {
            onChanged(proposal.copyWith(name: trimmed, userEdited: true))
        }
        editingName = false
    }

    private var headerRow: some View {
        HStack(spacing: FkSpacing.sm) {
            Button(action: onToggleSelected) {
                Image(systemName: proposal.selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(proposal.selected ? Color.fkPrimary : Color.fkOutline)
            }
            .buttonStyle(.fkPressable)

            provenanceBadge

            nameField

            Spacer(minLength: FkSpacing.sm)

            ProposalActionChip(
                action: proposal.action,
                mergeTargetLabel: proposal.mergeTargetLabel,
                locked: IntakeReviewStore.isActionLocked(proposal),
                onToggle: onToggleAction
            )
            .frame(maxWidth: 168, alignment: .trailing)
        }
    }

    /// Small colored dot marking the proposal field's provenance. `userEdited`
    /// always wins (手改); otherwise the dot reflects the data's origin.
    private var provenanceBadge: some View {
        Circle()
            .fill(provenanceColor)
            .frame(width: 8, height: 8)
            .accessibilityLabel(provenanceLabel)
    }

    private var provenanceColor: Color {
        if proposal.userEdited { return .fkWarn }
        switch proposal.origin {
        case .ai: return .fkPrimary
        case .system: return .fkOutline
        case .user: return .fkWarn
        }
    }

    private var provenanceLabel: String {
        if proposal.userEdited { return "手改" }
        switch proposal.origin {
        case .ai: return "AI 推断"
        case .system: return "系统"
        case .user: return "手填"
        }
    }

    private var metaRow: some View {
        HStack(spacing: FkSpacing.lg) {
            HStack(spacing: FkSpacing.sm) {
                Text("数量")
                    .font(.fkLabelMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                FkInlineStepper(value: proposal.quantity, min: 1) {
                    onChanged(proposal.copyWith(quantity: $0, userEdited: true))
                }
                Button(action: { showUnitPicker = true }) {
                    Text(proposal.unit)
                        .font(.fkLabelMedium)
                        .foregroundStyle(Color.fkPrimaryContainer)
                        .padding(.horizontal, FkSpacing.sm)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.fkPrimarySoft))
                }
                .buttonStyle(.fkPressable)
            }
            Spacer(minLength: 0)
        }
    }

    private var pickerRow: some View {
        HStack(spacing: FkSpacing.sm) {
            chip("分类:\(FoodCategories.dropdownValue(proposal.category))") { showCategoryPicker = true }
            chip("存:\(proposal.storage.storageAreaLabel)") { showStoragePicker = true }
            shelfLifeChip
            Spacer(minLength: 0)
        }
    }

    private var shelfLifeChip: some View {
        let days = proposal.shelfLifeDays ?? 0
        let label = days > 0 ? "保质期:\(days)天" : "保质期:未设置"
        return Button {
            // Tap toggles a sensible default on when unset; otherwise opens nothing
            // destructive — re-tapping cycles 7→14→30→nil for quick adjustment.
            switch days {
            case 0: onChanged(proposal.copyWith(shelfLifeDays: 7, userEdited: true))
            case ..<14: onChanged(proposal.copyWith(shelfLifeDays: 14, userEdited: true))
            case ..<30: onChanged(proposal.copyWith(shelfLifeDays: 30, userEdited: true))
            default: onChanged(proposal.copyWith(userEdited: true, clearShelfLifeDays: true))
            }
        } label: {
            Text(label)
                .font(.fkLabelMedium)
                .foregroundStyle(Color.fkOnSurfaceVariant)
                .padding(.horizontal, FkSpacing.md)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.fkSurfaceContainer))
        }
        .buttonStyle(.fkPressable)
    }

    private func chip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.fkLabelMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.fkOutline)
            }
            .padding(.horizontal, FkSpacing.md)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.fkSurfaceContainer))
        }
        .buttonStyle(.fkPressable)
    }
}
