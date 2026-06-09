import SwiftUI

/// Manual add-ingredient form, presented as a sheet from the 库存 toolbar "+".
///
/// Fields: name (commits smart-default autofill from `FoodKnowledge`), quantity
/// + unit, category, storage, and shelf-life (presets [3,7,14,30] + 自定义 + 不
/// 过期). On submit it builds ONE `IntakeProposal` via `IntakeProposalFactory`
/// (so the merge-vs-new-batch default is correct), then:
///   - a brand-new row (`.newRow`) applies directly through `IntakeController`
///     and dismisses (the fast manual path),
///   - a row that would MERGE into an existing batch is pushed to
///     `IntakeReviewView` so the user confirms the merge (an append-only direct
///     apply would otherwise risk a surprise quantity bump).
///
/// Either way the actual apply runs through the same P4 `ProposalApply`
/// pipeline, so identity re-resolution + freshness refresh are preserved.
struct AddIngredientView: View {
    /// Called after a successful apply so the caller can refresh the inventory.
    var onApplied: () -> Void = {}

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var form = AddIngredientForm()
    @State private var reviewRoute: ReviewRoute?
    @State private var isSubmitting = false
    @State private var showUnitPicker = false
    @State private var showCategoryPicker = false
    @State private var showStoragePicker = false
    @State private var showPasteImport = false
    @State private var showImageImport = false
    @State private var showScanner = false
    @State private var showScannerUnavailable = false
    @State private var isLookingUpBarcode = false
    @State private var barcodeNotice: String?
    @State private var customShelfLife = ""
    /// 常购食材 quick-fill chips, loaded from the add-history frequency memory.
    @State private var frequentItems: [FrequentItem] = []
    @FocusState private var nameFocused: Bool

    private var controller: IntakeController {
        IntakeController(
            repository: dependencies.inventoryRepository,
            householdID: dependencies.householdID,
            syncWriter: dependencies.syncWriter
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FkSpacing.lg) {
                    pasteImportButton
                    imageImportButton
                    scanButton
                    if let barcodeNotice {
                        FkBarcodeNotice(message: barcodeNotice)
                    }
                    nameField
                    quantityRow
                    categoryField
                    storageField
                    shelfLifeField
                    frequentItemsSection
                }
                .padding(FkSpacing.lg)
            }
            .background(Color.fkSurface)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("添加食材")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSubmitting ? "添加中…" : "添加") { Task { await submit() } }
                        .font(.fkLabelLarge)
                        .disabled(!form.canSubmit || isSubmitting)
                }
            }
            .navigationDestination(item: $reviewRoute) { route in
                IntakeReviewView(proposals: route.proposals, title: "确认入库") { _ in
                    onApplied()
                    dismiss()
                }
            }
            .sheet(isPresented: $showUnitPicker) {
                FkPickerSheet(
                    title: "选择单位",
                    options: form.unitOptions.map { FkPickerOption(value: $0, label: $0) },
                    selected: form.unit
                ) { form.setUnit($0) }
            }
            .sheet(isPresented: $showCategoryPicker) {
                FkPickerSheet(
                    title: "选择分类",
                    options: FoodCategories.values.map { FkPickerOption(value: $0, label: $0) },
                    selected: FoodCategories.dropdownValue(form.category)
                ) { form.setCategory($0) }
            }
            .sheet(isPresented: $showStoragePicker) {
                FkPickerSheet(
                    title: "存放位置",
                    options: IconType.allCases.map { FkPickerOption(value: $0, label: $0.storageAreaLabel) },
                    selected: form.storage
                ) { form.setStorage($0) }
            }
            .sheet(isPresented: $showPasteImport) {
                PasteImportView(aiSettings: dependencies.aiSettingsStore.settings) {
                    onApplied()
                    dismiss()
                }
            }
            .sheet(isPresented: $showImageImport) {
                ImageImportView(aiSettings: dependencies.aiSettingsStore.settings) {
                    onApplied()
                    dismiss()
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                BarcodeScannerScreen { code in
                    Task { await handleScannedBarcode(code) }
                }
            }
            .alert("无法扫码", isPresented: $showScannerUnavailable) {
                Button("好", role: .cancel) {}
            } message: {
                Text("此设备不支持扫码，请在真机上使用，或手动填写。")
            }
            .overlay {
                if isLookingUpBarcode {
                    BarcodeLookupBusyOverlay()
                }
            }
        }
        .onAppear { nameFocused = true }
        .task {
            if frequentItems.isEmpty {
                let all = (try? await dependencies.inventoryRepository.loadFrequentItems()) ?? []
                frequentItems = Array(all.prefix(8))
            }
        }
    }

    /// 常购食材 quick-fill: tapping a chip seeds the whole form from a remembered
    /// frequent item (mirrors the Flutter add form's `_FrequentItemsSection`).
    @ViewBuilder
    private var frequentItemsSection: some View {
        if !frequentItems.isEmpty {
            FkFormField(label: "常购食材") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FkSpacing.sm) {
                        ForEach(frequentItems, id: \.name) { item in
                            Button {
                                form.applyFrequentItem(item)
                                customShelfLife = ""
                                nameFocused = false
                            } label: {
                                HStack(spacing: FkSpacing.xs) {
                                    Image(systemName: storageIconName(item.storage))
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(item.name)
                                        .font(.fkLabelMedium)
                                }
                                .foregroundStyle(Color.fkPrimary)
                                .padding(.horizontal, FkSpacing.md)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.fkPrimarySoft))
                            }
                            .buttonStyle(.fkPressable)
                        }
                    }
                }
            }
        }
    }

    private func storageIconName(_ storage: IconType) -> String {
        switch storage {
        case .fridge: return "refrigerator"
        case .freezer: return "snowflake"
        case .pantry: return "cabinet"
        }
    }

    // MARK: Fields

    /// "AI 解析文本" entry point — always visible; routes to a "去配置" note inside
    /// the sheet when no AI provider is configured (mirrors the local-only flows).
    private var pasteImportButton: some View {
        Button {
            nameFocused = false
            showPasteImport = true
        } label: {
            HStack(spacing: FkSpacing.sm) {
                Image(systemName: "wand.and.stars")
                Text("AI 解析文本")
                    .font(.fkLabelLarge)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.fkOutline)
            }
            .foregroundStyle(Color.fkPrimary)
            .padding(FkSpacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                    .fill(Color.fkPrimarySoft)
            )
        }
        .buttonStyle(.fkPressable)
    }

    /// "拍照/相册识别" entry point — opens the AI vision import sheet; routes to a
    /// "去配置" note inside the sheet when no AI provider is configured (mirrors the
    /// text paste-import flow).
    private var imageImportButton: some View {
        Button {
            nameFocused = false
            showImageImport = true
        } label: {
            HStack(spacing: FkSpacing.sm) {
                Image(systemName: "camera.viewfinder")
                Text("拍照/相册识别")
                    .font(.fkLabelLarge)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.fkOutline)
            }
            .foregroundStyle(Color.fkPrimary)
            .padding(FkSpacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                    .fill(Color.fkPrimarySoft)
            )
        }
        .buttonStyle(.fkPressable)
    }

    /// "扫码添加" entry point — opens the live barcode scanner when this device
    /// supports it, else surfaces a "请在真机使用" alert (never a black screen /
    /// crash on the simulator). On a scan the barcode is looked up on OFF and the
    /// form is prefilled in place.
    private var scanButton: some View {
        Button {
            nameFocused = false
            barcodeNotice = nil
            if BarcodeScannerView.isScanningAvailable {
                showScanner = true
            } else {
                showScannerUnavailable = true
            }
        } label: {
            HStack(spacing: FkSpacing.sm) {
                Image(systemName: "barcode.viewfinder")
                Text("扫码添加")
                    .font(.fkLabelLarge)
                if !BarcodeScannerView.isScanningAvailable {
                    Text("需真机")
                        .font(.fkLabelSmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.fkOutline)
            }
            .foregroundStyle(Color.fkPrimary)
            .padding(FkSpacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                    .fill(Color.fkPrimarySoft)
            )
        }
        .buttonStyle(.fkPressable)
    }

    private var nameField: some View {
        FkFormField(label: "名称") {
            FkTextFieldPill(
                text: $form.name,
                placeholder: "如:牛奶、鸡蛋",
                submitLabel: .next,
                onCommit: { form.applySmartDefaults() }
            )
            .focused($nameFocused)
            .onChange(of: nameFocused) { _, focused in
                // Apply smart defaults on blur too (not just keyboard submit).
                if !focused { form.applySmartDefaults() }
            }
        }
    }

    private var quantityRow: some View {
        HStack(alignment: .bottom, spacing: FkSpacing.md) {
            FkFormField(label: "数量") {
                FkTextFieldPill(
                    text: $form.quantity,
                    placeholder: "1",
                    keyboard: .decimalPad
                )
            }
            FkFormField(label: "单位") {
                FkValuePill(value: form.unit) { showUnitPicker = true }
            }
            .frame(maxWidth: 140)
        }
    }

    private var categoryField: some View {
        FkFormField(label: "分类") {
            FkValuePill(value: FoodCategories.dropdownValue(form.category)) {
                showCategoryPicker = true
            }
        }
    }

    private var storageField: some View {
        FkFormField(label: "存放位置") {
            FkValuePill(value: form.storage.storageAreaLabel, systemImage: storageIcon) {
                showStoragePicker = true
            }
        }
    }

    private var shelfLifeField: some View {
        FkFormField(label: "保质期") {
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FkSpacing.sm) {
                        ForEach(form.shelfLifePresets, id: \.self) { days in
                            FkChip(
                                label: "\(days)天",
                                isSelected: form.shelfLifeDays == days
                            ) {
                                customShelfLife = ""
                                form.setShelfLife(days)
                            }
                        }
                        FkChip(label: "不过期", isSelected: form.shelfLifeDays == nil && customShelfLife.isEmpty) {
                            customShelfLife = ""
                            form.setShelfLife(nil)
                        }
                    }
                }
                HStack(spacing: FkSpacing.sm) {
                    Text("自定义")
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                    TextField("天数", text: $customShelfLife)
                        .font(.fkTitleMedium)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 80)
                        .padding(.horizontal, FkSpacing.sm)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: FkRadius.sm, style: .continuous)
                                .fill(Color.fkSurfaceContainer)
                        )
                        .onChange(of: customShelfLife) { _, value in
                            if let days = Int(value.trimmed), days > 0 {
                                form.setShelfLife(days)
                            }
                        }
                    Text("天")
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
        }
    }

    private var storageIcon: String {
        switch form.storage {
        case .fridge: return "refrigerator"
        case .freezer: return "snowflake"
        case .pantry: return "cabinet"
        }
    }

    // MARK: Barcode scan

    /// Looks the scanned barcode up on Open Food Facts and prefills the form in
    /// place (reusing the manual add path — the user reviews + taps 添加). On a
    /// nil OFF result the form keeps just the barcode + shows a gentle notice so
    /// the user can still fill it in by hand.
    private func handleScannedBarcode(_ code: String) async {
        let barcode = code.trimmed
        guard !barcode.isEmpty else { return }

        isLookingUpBarcode = true
        defer { isLookingUpBarcode = false }

        let details = await OpenFoodFactsService.lookupDetails(name: "", barcode: barcode)
        form.prefill(from: details, barcode: barcode)
        barcodeNotice = details == nil ? "未找到该条码的产品信息，请手动补充。" : nil
        nameFocused = false
    }

    // MARK: Submit

    private func submit() async {
        guard form.canSubmit, !isSubmitting else { return }
        nameFocused = false
        form.applySmartDefaults()
        isSubmitting = true
        defer { isSubmitting = false }

        let inventory = (try? await dependencies.inventoryRepository.loadAllFor(dependencies.householdID)) ?? []
        let proposal = form.buildProposal(inventory: inventory)

        // A new batch applies directly (fast manual path); a merge routes through
        // Review so the user confirms the surprise quantity bump.
        if proposal.action == .mergeInto {
            reviewRoute = ReviewRoute(proposals: [proposal])
            return
        }

        let outcome = await controller.apply([proposal])
        if outcome.persisted {
            onApplied()
            dismiss()
        }
    }
}

/// Compact inline notice row for the barcode flow — e.g. "未找到该条码的产品信息"
/// after a scan that OFF couldn't resolve. Mirrors `FkImageImportNotice`.
private struct FkBarcodeNotice: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: FkSpacing.sm) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.fkPrimary)
            Text(message)
                .font(.fkBodyMedium)
                .foregroundStyle(Color.fkOnSurface)
            Spacer(minLength: 0)
        }
        .padding(FkSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                .fill(Color.fkPrimarySoft)
        )
    }
}

/// Dimmed busy overlay shown while the scanned barcode is looked up on OFF —
/// blocks edits + signals progress (mirrors the AI import overlays).
private struct BarcodeLookupBusyOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            VStack(spacing: FkSpacing.md) {
                ProgressView()
                    .controlSize(.large)
                Text("查询条码中…")
                    .font(.fkLabelLarge)
                    .foregroundStyle(Color.fkOnSurface)
            }
            .padding(FkSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                    .fill(Color.fkSurfaceContainerHighest)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("查询条码中")
    }
}

/// `Identifiable` wrapper around the proposals so they can drive a
/// `navigationDestination(item:)` push to the review screen (the domain
/// `IntakeProposal` is deliberately not `Hashable`/`Identifiable`). Shared by the
/// manual add and the AI paste-import flows.
struct ReviewRoute: Identifiable, Hashable {
    let proposals: [IntakeProposal]
    var id: String { proposals.map(\.id).joined(separator: "|") }

    static func == (lhs: ReviewRoute, rhs: ReviewRoute) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
