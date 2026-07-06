import PhotosUI
import SwiftUI
import os

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
    @State private var showReceiptImport = false
    @State private var showPaywall = false
    @State private var showScanner = false
    @State private var showScannerUnavailable = false
    @State private var isLookingUpBarcode = false
    @State private var barcodeNotice: String?
    @State private var customShelfLife = ""
    /// 常购食材 quick-fill chips, loaded from the add-history frequency memory.
    @State private var frequentItems: [FrequentItem] = []
    /// Photo picked for the "拍照识别保质期" OCR flow; nil between picks.
    @State private var pickedExpiryPhoto: PhotosPickerItem?
    /// True while the expiry photo is being OCR'd + parsed (blocks a re-pick).
    @State private var isRecognizingExpiry = false
    /// Inline notice under the shelf-life field after an expiry scan — a success
    /// hint or a "未识别到日期，请手动填写" failure. Never silent, never auto-filled.
    @State private var expiryScanNotice: ExpiryScanNotice?
    /// Inline failure notice for the submit path — the inventory load or the
    /// apply/persist threw. The sheet stays open with the form intact so a retry
    /// is one tap away (the `IntakeController` contract: the caller surfaces the
    /// retry). Cleared when the next submit starts.
    @State private var submitError: String?
    @FocusState private var nameFocused: Bool

    /// Barcode-memory is a convenience cache, never a data path: failures here
    /// degrade to OFF / manual and are only logged (debug), never surfaced.
    private static let barcodeLogger = Logger(subsystem: "com.sunpebble.freshpantry", category: "barcode-memory")

    private var controller: IntakeController {
        IntakeController(
            repository: dependencies.inventoryRepository,
            householdID: dependencies.householdID,
            syncWriter: dependencies.syncWriter,
            isPro: { dependencies.proStore.isPro }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FkSpacing.lg) {
                    if let submitError {
                        // 失败留在本屏可重试：库存一行没进、表单原样保留，不提示的
                        // 话只会看到按钮闪回「添加」（mirrors IntakeReviewView）。
                        FkSubmitErrorNotice(message: submitError)
                    }
                    pasteImportButton
                    imageImportButton
                    receiptImportButton
                    scanButton
                    if let barcodeNotice {
                        FkBarcodeNotice(message: barcodeNotice)
                    }
                    nameField
                    quantityRow
                    categoryField
                    storageField
                    shelfLifeField
                    tagsField
                    frequentItemsSection
                }
                .padding(FkSpacing.lg)
            }
            .background(Color.fkSurface)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(String(localized: "inventory.addIngredient.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "inventory.action.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSubmitting ? String(localized: "inventory.addIngredient.adding") : String(localized: "inventory.addIngredient.add")) { Task { await submit() } }
                        .font(.fkLabelLarge)
                        .disabled(!form.canSubmit || isSubmitting)
                }
            }
            .navigationDestination(item: $reviewRoute) { route in
                IntakeReviewView(proposals: route.proposals, title: String(localized: "inventory.intakeReview.confirmTitle")) { _ in
                    // The merge path also confirmed a save → learn the barcode
                    // before tearing down (the form still holds it). Fire-and-
                    // forget so dismissal isn't gated on the convenience write.
                    Task { await learnScannedBarcode() }
                    onApplied()
                    dismiss()
                }
            }
            .sheet(isPresented: $showUnitPicker) {
                FkPickerSheet(
                    title: String(localized: "inventory.picker.unit"),
                    options: form.unitOptions.map { FkPickerOption(value: $0, label: UnitLabels.displayLabel(for: $0)) },
                    selected: form.unit
                ) { form.setUnit($0) }
            }
            .sheet(isPresented: $showCategoryPicker) {
                FkPickerSheet(
                    title: String(localized: "inventory.picker.category"),
                    options: FoodCategories.values.map { FkPickerOption(value: $0, label: FoodCategories.displayLabel(for: $0)) },
                    selected: FoodCategories.dropdownValue(form.category)
                ) { form.setCategory($0) }
            }
            .sheet(isPresented: $showStoragePicker) {
                FkPickerSheet(
                    title: String(localized: "inventory.picker.storage"),
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
            .sheet(isPresented: $showReceiptImport) {
                ReceiptImportView(aiSettings: dependencies.aiSettingsStore.settings) {
                    onApplied()
                    dismiss()
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallSheet(proStore: dependencies.proStore)
            }
            .fullScreenCover(isPresented: $showScanner) {
                BarcodeScannerScreen { code in
                    Task { await handleScannedBarcode(code) }
                }
            }
            .alert(String(localized: "inventory.scan.unavailableTitle"), isPresented: $showScannerUnavailable) {
                Button(String(localized: "inventory.action.ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "inventory.scan.unavailableMessage"))
            }
            .overlay {
                if isLookingUpBarcode {
                    FkBusyOverlay(text: String(localized: "inventory.scan.lookingUpBarcode"))
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
            FkFormField(label: String(localized: "inventory.frequentItems.label")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FkSpacing.sm) {
                        ForEach(frequentItems, id: \.name) { item in
                            Button {
                                form.applyFrequentItem(item)
                                customShelfLife = ""
                                nameFocused = false
                            } label: {
                                HStack(spacing: FkSpacing.xs) {
                                    Image(systemName: item.storage.sfSymbolOutline)
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
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task {
                                        // Optimistic: the chip vanishes the instant 忘记 is
                                        // tapped; re-add it if the persist throws.
                                        let snapshot = frequentItems
                                        frequentItems.removeAll { $0.name == item.name }
                                        do {
                                            try await dependencies.inventoryRepository.forgetAddition(item.name)
                                        } catch {
                                            frequentItems = snapshot
                                        }
                                    }
                                } label: {
                                    Label(String(localized: "inventory.frequentItems.forget"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
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
                Text(String(localized: "inventory.import.pasteText"))
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
                Text(String(localized: "inventory.import.photoRecognize"))
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

    /// "扫小票入库" entry point — pick/shoot a shopping receipt, OCR it on-device,
    /// then feed the text into the SAME AI text-parse → review chain. Routes to a
    /// "去配置" note inside the sheet when no AI provider is configured (the parse
    /// step needs the LLM), mirroring the other AI import flows.
    private var receiptImportButton: some View {
        Button {
            nameFocused = false
            showReceiptImport = true
        } label: {
            HStack(spacing: FkSpacing.sm) {
                Image(systemName: "doc.text.viewfinder")
                Text(String(localized: "inventory.import.receipt"))
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
                Text(String(localized: "inventory.import.scanBarcode"))
                    .font(.fkLabelLarge)
                if !BarcodeScannerView.isScanningAvailable {
                    Text(String(localized: "inventory.scan.requiresDevice"))
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
        FkFormField(label: String(localized: "inventory.field.name")) {
            FkTextFieldPill(
                text: $form.name,
                placeholder: String(localized: "inventory.field.namePlaceholder"),
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
            FkFormField(label: String(localized: "inventory.field.quantity")) {
                FkTextFieldPill(
                    text: $form.quantity,
                    placeholder: "1",
                    keyboard: .decimalPad
                )
            }
            FkFormField(label: String(localized: "inventory.field.unit")) {
                FkValuePill(value: UnitLabels.displayLabel(for: form.unit)) { showUnitPicker = true }
            }
            .frame(maxWidth: 140)
        }
    }

    private var categoryField: some View {
        FkFormField(label: String(localized: "inventory.field.category")) {
            FkValuePill(value: FoodCategories.displayLabel(for: FoodCategories.dropdownValue(form.category))) {
                showCategoryPicker = true
            }
        }
    }

    private var storageField: some View {
        FkFormField(label: String(localized: "inventory.field.storage")) {
            FkValuePill(value: form.storage.storageAreaLabel, systemImage: form.storage.sfSymbolOutline) {
                showStoragePicker = true
            }
        }
    }

    private var shelfLifeField: some View {
        FkFormField(label: String(localized: "inventory.field.shelfLife")) {
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FkSpacing.sm) {
                        ForEach(form.shelfLifePresets, id: \.self) { days in
                            FkChip(
                                label: String(localized: "inventory.shelfLife.days \(days)"),
                                isSelected: form.shelfLifeDays == days
                            ) {
                                customShelfLife = ""
                                expiryScanNotice = nil
                                form.setShelfLife(days)
                            }
                        }
                        FkChip(label: String(localized: "inventory.shelfLife.never"), isSelected: form.shelfLifeDays == nil && customShelfLife.isEmpty) {
                            customShelfLife = ""
                            expiryScanNotice = nil
                            form.setShelfLife(nil)
                        }
                    }
                }
                HStack(spacing: FkSpacing.sm) {
                    Text(String(localized: "inventory.shelfLife.custom"))
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                    TextField(String(localized: "inventory.shelfLife.dayCount"), text: $customShelfLife)
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
                                expiryScanNotice = nil
                                form.setShelfLife(days)
                            }
                        }
                    Text(String(localized: "inventory.shelfLife.unitDay"))
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
                scanExpiryButton
                if let expiryScanNotice {
                    FkExpiryScanNotice(notice: expiryScanNotice)
                }
            }
        }
    }

    /// "拍照识别保质期" entry — pick a packaging photo, OCR it on-device
    /// (`TextRecognizer`), parse the most likely expiry (`ExpiryDateParser`), and
    /// prefill the shelf-life. No AI provider needed (recognition is fully local).
    /// A miss surfaces an inline "请手动填写" notice and never blocks the form.
    private var scanExpiryButton: some View {
        // Snapshot the main-actor @State into a Sendable local: the PhotosPicker
        // `label` closure is inferred nonisolated, so it can't read `self` state
        // directly (the value re-reads on every body re-eval, so it stays live).
        let recognizing = isRecognizingExpiry
        return PhotosPicker(
            selection: $pickedExpiryPhoto,
            matching: .images,
            photoLibrary: .shared()
        ) {
            HStack(spacing: FkSpacing.xs) {
                if recognizing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(recognizing ? String(localized: "inventory.expiryScan.recognizing") : String(localized: "inventory.expiryScan.action"))
                    .font(.fkLabelMedium)
            }
            .foregroundStyle(Color.fkPrimary)
            .padding(.horizontal, FkSpacing.md)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.fkPrimarySoft))
        }
        .buttonStyle(.fkPressable)
        .disabled(isRecognizingExpiry)
        .onChange(of: pickedExpiryPhoto) { _, item in
            guard let item else { return }
            Task { await handlePickedExpiryPhoto(item) }
        }
    }

    private var tagsField: some View {
        FkFormField(label: String(localized: "inventory.field.tags")) {
            IngredientTagsEditor(tags: $form.tags)
        }
    }

    // MARK: Barcode scan

    /// Resolves a scanned barcode and prefills the form in place by priority:
    /// device-local memory (a product saved here before) → Open Food Facts →
    /// manual fallback. Reuses the manual add path (the user reviews + taps 添加).
    ///
    /// Local memory wins so a re-scan of a常买 product is instant + offline, and
    /// an OFF miss no longer dead-ends the user — they land in the form with just
    /// the barcode prefilled. The local lookup is best-effort: a failure is logged
    /// (debug) and silently degrades to the OFF lookup.
    private func handleScannedBarcode(_ code: String) async {
        let barcode = code.trimmed
        guard !barcode.isEmpty else { return }

        isLookingUpBarcode = true
        defer { isLookingUpBarcode = false }

        var localMemory: BarcodeMemory?
        do {
            localMemory = try await dependencies.barcodeMemoryRepository.lookup(barcode)
        } catch {
            Self.barcodeLogger.debug("barcode-memory lookup failed: \(error.localizedDescription, privacy: .public)")
        }

        // Only hit the network when local memory missed (avoids a needless OFF
        // round-trip for a product we already learned).
        let offDetails = localMemory == nil
            ? await OpenFoodFactsService.lookupDetails(name: "", barcode: barcode)
            : nil

        switch BarcodeScanResolution.decide(barcode: barcode, localMemory: localMemory, offDetails: offDetails) {
        case let .localMemory(name, category):
            form.prefill(fromLocalName: name, category: category, barcode: barcode)
            barcodeNotice = String(localized: "inventory.barcode.localMemoryApplied")
        case let .openFoodFacts(details):
            form.prefill(from: details, barcode: barcode)
            barcodeNotice = nil
        case .manualFallback:
            form.prefill(from: nil, barcode: barcode)
            barcodeNotice = String(localized: "inventory.barcode.notFound")
        case .invalid:
            break
        }
        nameFocused = false
    }

    /// Learns the scanned product after a successful save: remembers
    /// barcode → name + category on THIS device so the next scan fills instantly.
    /// Only fires when the form carries a scanned barcode. Best-effort — a write
    /// failure is logged (debug) and swallowed (it must never break a save that
    /// already persisted). No-op for hand-started adds (no barcode).
    private func learnScannedBarcode() async {
        guard let barcode = form.barcode?.trimmed, !barcode.isEmpty else { return }
        let name = form.name.trimmed
        guard !name.isEmpty else { return }
        do {
            try await dependencies.barcodeMemoryRepository.upsert(
                barcode: barcode,
                name: name,
                category: FoodCategories.dropdownValue(form.category)
            )
        } catch {
            Self.barcodeLogger.debug("barcode-memory upsert failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Expiry OCR

    /// Longest edge (px) the picked photo is downscaled to before OCR — bounds the
    /// Vision decode cost without losing the (usually large) printed date glyphs.
    private static let maxExpiryImageDimension = 1600

    /// Loads the picked packaging photo, runs on-device OCR + the pure expiry parser,
    /// and prefills the shelf-life. Every failure mode is surfaced inline (load /
    /// no-text / no-date / past-date), never silent and never an invented value, so
    /// the user always knows to fall back to manual entry. Resets the picker
    /// selection at the end so the SAME photo can be re-picked after a retry.
    private func handlePickedExpiryPhoto(_ item: PhotosPickerItem) async {
        nameFocused = false
        expiryScanNotice = nil
        isRecognizingExpiry = true
        defer {
            isRecognizingExpiry = false
            pickedExpiryPhoto = nil
        }

        let data: Data?
        do {
            data = try await item.loadTransferable(type: Data.self)
        } catch {
            expiryScanNotice = .failure(String(localized: "inventory.photo.loadFailed \(error.localizedDescription)"))
            return
        }
        guard let data, !data.isEmpty else {
            expiryScanNotice = .failure(String(localized: "inventory.photo.loadFailedRetry"))
            return
        }

        // Downscale off the main actor so a large photo never blocks the UI; fall
        // back to the original bytes if re-encode fails (OCR can still try).
        let maxDimension = Self.maxExpiryImageDimension
        let prepared = await Task.detached {
            ImageDownscaler.jpegData(from: data, maxDimension: maxDimension)
        }.value ?? data

        let lines: [String]
        do {
            lines = try await TextRecognizer.recognizeLines(from: prepared)
        } catch let error as TextRecognizer.RecognizeError {
            // OCR found no usable text (or couldn't decode) → manual-entry prompt.
            expiryScanNotice = .failure(error == .noText ? Self.noDateMessage : error.message)
            return
        } catch {
            expiryScanNotice = .failure(String(localized: "inventory.expiryScan.recognizeFailed \(error.localizedDescription)"))
            return
        }

        let text = lines.joined(separator: "\n")
        guard let expiry = ExpiryDateParser.parse(text) else {
            expiryScanNotice = .failure(Self.noDateMessage)
            return
        }
        guard let days = form.prefillExpiry(date: expiry) else {
            // Parsed a date, but it's today / already past — a stale label. Tell the
            // user rather than silently setting a 0/negative shelf life.
            expiryScanNotice = .failure(String(localized: "inventory.expiryScan.pastDate"))
            return
        }
        customShelfLife = ""
        expiryScanNotice = .success(String(localized: "inventory.expiryScan.recognized \(days)"))
    }

    /// Shared "no date found" copy — keeps the OCR-no-text and parser-no-date paths
    /// pointing the user at manual entry with one consistent message.
    private static let noDateMessage = String(localized: "inventory.expiryScan.noDate")

    // MARK: Submit

    private func submit() async {
        guard form.canSubmit, !isSubmitting else { return }
        nameFocused = false
        form.applySmartDefaults()
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        // The live inventory decides merge-vs-new-batch. A load failure must NOT
        // degrade to an empty inventory — that would force `.newRow` and silently
        // bypass the merge review — so the submit stops here with a retry notice.
        let inventory: [Ingredient]
        do {
            inventory = try await dependencies.inventoryRepository.loadAllFor(dependencies.householdID)
        } catch {
            submitError = AddSubmitFeedback.loadFailureMessage
            return
        }
        let proposal = form.buildProposal(inventory: inventory)

        // A new batch applies directly (fast manual path); a merge routes through
        // Review so the user confirms the surprise quantity bump.
        if proposal.action == .mergeInto {
            reviewRoute = ReviewRoute(proposals: [proposal])
            return
        }

        let outcome = await controller.apply([proposal])
        if outcome.limitReached {
            submitError = Self.inventoryLimitMessage
            showPaywall = true
        } else if outcome.persisted {
            await learnScannedBarcode()
            onApplied()
            await dependencies.notificationCoordinator.reschedule(householdID: dependencies.householdID)
            dismiss()
        } else {
            // The save threw → nothing was written (controller contract). Keep
            // the sheet open with an inline retry notice, never a silent no-op.
            submitError = AddSubmitFeedback.applyFailureMessage(for: outcome)
        }
    }

    private static var inventoryLimitMessage: String {
        String(localized: "inventory.freeTierLimit \(FreeTier.inventoryLimit)")
    }
}

/// Pure failure-copy mapping for the manual add's submit path, kept out of the
/// view so the branch is unit-testable (a real in-memory repository can't be
/// made to throw on demand). Mirrors `IntakeReviewStore.applyErrorMessage`.
@MainActor
enum AddSubmitFeedback {
    /// The live-inventory load threw BEFORE the proposal was built. Degrading to
    /// an empty inventory would force `.newRow` and silently bypass the merge
    /// review, so the submit fails loudly instead of guessing.
    static let loadFailureMessage = String(localized: "inventory.load.failedRetry")

    /// The apply didn't persist (the save threw; nothing was written). Same copy
    /// as the review screen so the retry hint reads identically on both paths.
    static func applyFailureMessage(for outcome: IntakeController.ApplyOutcome) -> String? {
        outcome.persisted || outcome.limitReached ? nil : String(localized: "inventory.intake.failedRetry")
    }
}

/// Danger-tinted inline notice for a failed submit (inventory load / persist
/// threw). Mirrors the styling of `FkBarcodeNotice` / `FkExpiryScanNotice`.
struct FkSubmitErrorNotice: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: FkSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.fkDanger)
            Text(message)
                .font(.fkBodyMedium)
                .foregroundStyle(Color.fkOnSurface)
            Spacer(minLength: 0)
        }
        .padding(FkSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                .fill(Color.fkDangerSoft)
        )
    }
}

/// Compact inline notice row for the barcode flow — e.g. "未找到该条码的产品信息"
/// after a scan that OFF couldn't resolve. Mirrors `FkInlineNotice`.
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

/// Outcome of an expiry-date OCR scan, surfaced inline under the shelf-life field.
/// A success carries the confirming hint; a failure carries the manual-entry
/// prompt. Either way the user is informed — the scan never silently no-ops.
enum ExpiryScanNotice: Equatable {
    case success(String)
    case failure(String)
}

/// Inline notice row for the "拍照识别保质期" flow — a green-tinted confirmation on
/// success or a danger-tinted "请手动填写" prompt on failure. Mirrors the styling of
/// `FkBarcodeNotice` / `FkInlineNotice`.
private struct FkExpiryScanNotice: View {
    let notice: ExpiryScanNotice

    private var isSuccess: Bool {
        if case .success = notice { return true }
        return false
    }

    private var message: String {
        switch notice {
        case let .success(text), let .failure(text): return text
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: FkSpacing.sm) {
            Image(systemName: isSuccess ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(isSuccess ? Color.fkPrimary : Color.fkDanger)
            Text(message)
                .font(.fkBodyMedium)
                .foregroundStyle(Color.fkOnSurface)
            Spacer(minLength: 0)
        }
        .padding(FkSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                .fill(isSuccess ? Color.fkPrimarySoft : Color.fkDangerSoft)
        )
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
