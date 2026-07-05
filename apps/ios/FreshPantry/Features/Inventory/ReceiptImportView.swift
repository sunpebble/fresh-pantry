import PhotosUI
import SwiftUI

/// 扫小票批量入库 sheet: pick (or shoot) a shopping-receipt photo, OCR it ON-DEVICE
/// via `TextRecognizer` (no network), then feed the recognized text into the EXACT
/// same `PasteImportStore` text-parse chain the "AI 解析文本" flow uses. The receipt
/// path is deliberately just a "photo → OCR → text" prefix in front of the existing
/// parser → `IntakeReviewView` machinery, so the apply + sync-enqueue logic is never
/// duplicated.
///
/// Gated on the same BYOK / 内置(Pro) / paywall 三态 as the other AI import paths
/// (`AiChatAccess.resolve`，the parse step needs the LLM) — 非 Pro 且未配置 BYOK
/// 弹 PaywallSheet。Uses `PhotosUI.PhotosPicker` (out-of-process), so it works in
/// the simulator and needs NO `NSPhotoLibraryUsageDescription`.
struct ReceiptImportView: View {
    let aiSettings: AiSettings
    /// Called after a successful apply so the presenter can refresh + dismiss the
    /// whole add flow.
    var onApplied: () -> Void = {}

    /// Longest edge (px) the picked receipt is downscaled to before OCR. Receipts
    /// are tall + text-dense, so allow more resolution than the vision-import path
    /// to keep small print legible to Vision.
    private static let maxImageDimension = 2048

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var store: PasteImportStore?
    @State private var reviewRoute: ReviewRoute?
    @State private var pickedItem: PhotosPickerItem?
    @State private var isRecognizing = false
    /// Local (pre-parse) errors: photo load / OCR failures. AI-parse errors live on
    /// `store.errorMessage` (shared with the text path).
    @State private var ocrError: String?
    /// Pro 门控：.needsPro 时弹 PaywallSheet。
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                // store 存在 ⇔ 三态解析出可用通道（见 .task）。
                if store != nil {
                    picker
                } else {
                    notConfigured
                }
            }
            .background(Color.fkSurface)
            .navigationTitle(String(localized: "inventory.import.receipt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "inventory.action.cancel")) { dismiss() }
                        .disabled(isBusy)
                }
            }
            .overlay {
                if isBusy {
                    FkBusyOverlay(text: isRecognizing ? String(localized: "inventory.receiptImport.recognizing") : String(localized: "inventory.import.aiRecognizing"))
                }
            }
            .navigationDestination(item: $reviewRoute) { route in
                IntakeReviewView(proposals: route.proposals, title: String(localized: "inventory.intakeReview.confirmTitle")) { _ in
                    onApplied()
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(proStore: dependencies.proStore)
        }
        // 三态解析后再建 store；id 绑 isPro，paywall 内购买成功后自动重解析进入选图。
        .task(id: dependencies.proStore.isPro) {
            guard store == nil else { return }
            switch AiChatAccess.resolve(byok: aiSettings, isPro: dependencies.proStore.isPro) {
            case .byok:
                store = PasteImportStore(
                    aiSettings: aiSettings,
                    inventoryRepository: dependencies.inventoryRepository,
                    householdID: dependencies.householdID
                )
            case .builtIn:
                // 本地模式（无 Supabase 后端）内置通道不可用 → 停在 notConfigured note。
                guard let chatFn = dependencies.builtInAiChatFn() else { return }
                store = PasteImportStore(
                    aiSettings: aiSettings,
                    inventoryRepository: dependencies.inventoryRepository,
                    householdID: dependencies.householdID,
                    chatFn: chatFn
                )
            case .needsPro:
                showPaywall = true
            }
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await handlePicked(item) }
        }
    }

    /// Busy while either OCR or the AI parse is running — blocks dismiss + repick.
    private var isBusy: Bool { isRecognizing || store?.isParsing == true }

    // MARK: Picker

    @ViewBuilder
    private var picker: some View {
        if let store {
            ScrollView {
                VStack(alignment: .leading, spacing: FkSpacing.lg) {
                    Text(String(localized: "inventory.receiptImport.subtitle"))
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)

                    PhotosPicker(
                        selection: $pickedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        pickerLabel
                    }
                    .buttonStyle(.fkPressable)
                    .disabled(isBusy)

                    if let message = ocrError ?? store.errorMessage {
                        FkInlineNotice(systemImage: "exclamationmark.triangle", message: message)
                    }
                }
                .padding(FkSpacing.lg)
            }
        }
    }

    // `nonisolated`: the label is static chrome (no @State), so it can be read
    // from PhotosPicker's nonisolated `label` closure without an isolation warning.
    nonisolated private var pickerLabel: some View {
        HStack(spacing: FkSpacing.sm) {
            Image(systemName: "doc.text.viewfinder")
            Text(String(localized: "inventory.receiptImport.choosePhoto"))
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

    private var notConfigured: some View {
        FkEmptyState(
            systemImage: "doc.text.viewfinder",
            title: String(localized: "inventory.ai.notConfiguredTitle"),
            message: String(localized: "inventory.receiptImport.notConfiguredMessage")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    /// photo → downscale → on-device OCR → feed recognized text into the SAME
    /// `PasteImportStore` text parse the "AI 解析文本" flow uses → push review.
    /// Failures (photo load / OCR) surface inline via `ocrError`; AI-parse failures
    /// surface via the shared `store.errorMessage`. Resets the picker selection at
    /// the end (success OR failure) so the SAME receipt can be re-picked after a
    /// retry — an identical pick never re-fires `onChange`.
    private func handlePicked(_ item: PhotosPickerItem) async {
        defer { pickedItem = nil }
        guard let store, !isBusy else { return }
        ocrError = nil

        let data: Data?
        do {
            data = try await item.loadTransferable(type: Data.self)
        } catch {
            ocrError = String(localized: "inventory.photo.loadFailed \(error.localizedDescription)")
            return
        }
        guard let data, !data.isEmpty else {
            ocrError = String(localized: "inventory.photo.loadFailedRetry")
            return
        }

        // Downscale off the main actor so a large receipt photo never blocks UI,
        // then OCR (also off-actor inside TextRecognizer).
        isRecognizing = true
        let maxDimension = Self.maxImageDimension
        let jpeg = await Task.detached {
            ImageDownscaler.jpegData(from: data, maxDimension: maxDimension)
        }.value
        guard let jpeg else {
            isRecognizing = false
            ocrError = String(localized: "inventory.photo.processFailed")
            return
        }

        let recognized: String
        do {
            recognized = try await TextRecognizer.recognizeReceiptText(from: jpeg)
        } catch let error as TextRecognizer.RecognizeError {
            isRecognizing = false
            ocrError = error.message
            return
        } catch {
            isRecognizing = false
            ocrError = String(localized: "inventory.receiptImport.recognizeFailed \(error.localizedDescription)")
            return
        }
        isRecognizing = false

        // Hand the recognized receipt text to the EXISTING text parse path — no
        // second pipeline. Proposals flow to the shared review screen exactly like
        // the paste-import flow.
        store.text = recognized
        await store.parse()
        if let proposals = store.proposals {
            reviewRoute = ReviewRoute(proposals: proposals)
            store.consumeProposals()
        }
    }
}
